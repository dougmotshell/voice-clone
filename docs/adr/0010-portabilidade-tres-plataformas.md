# ADR-0010 — Suporte a Linux, macOS e Windows

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

O projeto nasceu e foi medido numa única máquina Linux, e o código refletia
isso em quatro pontos concretos:

1. A detecção de cores físicos ([ADR-0005](0005-threads-cores-fisicos.md)) lia
   `/sys/devices/system/cpu/cpu0/topology/thread_siblings_list`. Fora do Linux o
   arquivo não existe e o recuo dividia as threads lógicas por dois.
2. As versões do PyTorch estavam só em prosa no README, e o índice CPU-only do
   PyTorch não tem wheels para macOS — instalar de lá quebra no Mac.
3. O nome da voz virava nome de arquivo sem validação. `a/b` já quebrava no
   Linux; no Windows quebram também `< > : " \ | ? *`, os nomes de dispositivo
   (`CON`, `NUL`, `COM1`…) e o ponto ou espaço no fim.
4. A quantização int8 ([ADR-0006](0006-quantizacao-int8-opcional.md)) assumia o
   backend `fbgemm` do x86; em ARM o backend é o `qnnpack` e a chamada pode
   falhar.

## Decisão

**Detecção de cores por `psutil`, com recuos por plataforma.** `psutil.cpu_count(logical=False)`
responde nas três plataformas. Os recuos ficam para o caso de o pacote faltar:
`/sys` no Linux, `sysctl -n hw.physicalcpu` no macOS. O recuo genérico — dividir
as lógicas por dois — passou a ser o **último**, e não o primeiro: em CPUs sem
SMT, como as Apple Silicon, físico e lógico coincidem, e dividir jogaria fora
metade da máquina.

**Manifesto com markers de plataforma.** `requirements.txt` passa a existir, com
as versões fixadas e a origem certa em cada sistema:

| Plataforma | Wheels | Por quê |
|---|---|---|
| Linux | `+cpu`, do índice do PyTorch | O wheel do PyPI arrasta ~2,5 GB de CUDA (as dependências `nvidia-*` têm marker `platform_system == "Linux"`) |
| Windows | PyPI ou `+cpu` — os dois servem | Não há build CUDA no PyPI para Windows |
| macOS | PyPI | Não há CUDA a evitar, e o índice do PyTorch não publica wheels para Mac |

O sufixo `+cpu` existe apenas no índice do PyTorch, então prende a resolução ao
wheel certo sem depender de ordem de índice. A alternativa — deixar a versão
solta e confiar na precedência de versão local do PEP 440 — foi rejeitada: se o
índice do PyTorch atrasar em relação ao PyPI, o resolvedor escolheria em
silêncio um build CUDA mais novo.

**`uv.toml` com `index-strategy = "unsafe-best-match"`.** Com a estratégia
padrão, `first-index`, o uv prende `torch` ao primeiro índice em que o encontra —
o do PyTorch — e a instalação no macOS falha por não haver wheel lá. A
estratégia permissiva olha os dois índices. Os dois são de primeira parte
(`pypi.org` e `download.pytorch.org`) e as versões estão fixadas, o que fecha a
porta para a confusão de dependência que o nome do modo adverte.

**Validação de nome de voz.** `vozclone.validar_nome()` aplica as regras do
sistema mais restritivo dos três a todos eles, e é chamada tanto no cadastro
quanto na busca. Uma voz cadastrada num sistema tem nome válido nos outros.

**Recuo da quantização.** Se `quantize_dynamic` falhar, o modo rápido avisa e
segue em float32 em vez de abortar a síntese.

**UTF-8 explícito na saída da CLI.** No Windows, com a saída redirecionada para
arquivo ou pipe, o encoding padrão é o do locale e os acentos levantam
`UnicodeEncodeError`.

## Consequências

**Positivas**
- Um único manifesto instala corretamente nas três plataformas, e o comando
  `checar` confirma o resultado no ambiente real.
- As decisões que estavam em prosa no README passaram a ser executáveis: o
  manifesto falha em vez de deixar entrar o build errado.
- Sem GPU exigida em nenhuma plataforma, mantendo o [ADR-0002](0002-pytorch-cpu-only.md).

**Negativas**
- **Só o Linux foi medido de fato.** A resolução de dependências foi verificada
  para as três plataformas (`uv pip compile --python-platform`), e a síntese
  completa, só no Linux. Os números de desempenho do SDD seguem valendo para
  aquele laptop e mais nada.
- **macOS exige Apple Silicon com macOS 14 ou mais recente.** O PyTorch não
  publica mais wheels para Mac Intel, e os de 2.12+ pedem macOS 14. Num Mac
  Intel é preciso recuar as versões do manifesto.
- Uma dependência nova (`psutil`), embora já viesse na árvore como transitiva.
- `index-strategy = "unsafe-best-match"` é mais permissivo que o padrão do uv.
  Aceito pelos dois motivos acima; se um terceiro índice entrar no projeto, a
  decisão precisa ser reavaliada.

## Revisão — 2026-08-23

A validação de nome descrita acima tinha **duas lacunas**, encontradas ao revisar
o que o SDD §7.3 afirmava sobre ela. A decisão não muda — aplicar as regras do
sistema mais restritivo em todas as plataformas —, mas a implementação estava
incompleta em dois pontos:

**1. Nome reservado com extensão passava.** A comparação era com o nome inteiro,
então `CON`, `NUL` e `LPT1` eram recusados, e `CON.wav`, `nul.txt` e `LPT1.mp3`
passavam. No Windows a reserva vale **com qualquer extensão**: `CON.wav` continua
sendo o dispositivo de console, e gravar ali não produz arquivo nenhum — a voz
seria "cadastrada" sem existir. A comparação passou a ser com o trecho antes do
primeiro ponto. `consultora` e `jarvis.v2` seguem válidos: a comparação é de
igualdade, não de prefixo.

**2. Não havia limite de comprimento.** Um nome de 300 caracteres passava e
estourava depois, na gravação, com erro cru do sistema:

```
OSError: [Errno 36] File name too long
```

Agora `NOME_MAX = 128` recusa antes, com mensagem em pt-BR dizendo o tamanho
recebido e o limite. 128 fica longe do teto de 255 bytes por componente no Linux
e no macOS, e deixa folga para os 260 do `MAX_PATH` no Windows sem long paths
habilitados.

A travessia de diretório, que o SDD §7.3 listava como **risco aceito**, nunca
existiu de fato: `..`, `../etc/passwd`, `a/b` e `a\b` já eram recusados desde a
decisão original, porque `/`, `\` e o ponto final estão todos no filtro. O que o
SDD registrava era uma afirmação desatualizada, não um furo — e foi corrigido
para descrever o controle em §7.2. Verificado com 25 casos, positivos e
negativos, mais uma síntese real depois da mudança.
