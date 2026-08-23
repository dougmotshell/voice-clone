# Software Design Document — Clonador de Voz Local

**Versão:** 1.0 · **Data:** 2026-08-23 · **Status:** Implementado

---

## 1. Introdução

### 1.1 Propósito

Este documento descreve o desenho do Clonador de Voz Local: um sistema que
aprende o timbre de uma voz a partir de um trecho curto de áudio e sintetiza
texto arbitrário nessa voz, operando inteiramente offline em CPU.

Destina-se a quem for manter, estender ou auditar o sistema. Para operação, veja
o [Manual](MANUAL.md). Para as decisões e seus porquês, os [ADRs](adr/). Para a
visão arquitetural em diagramas, o [modelo C4](c4/).

### 1.2 Escopo

**No escopo:** clonagem zero-shot de voz a partir de 6–30 s de referência;
síntese em pt-BR e en-US; operação local sem custo e sem rede; interfaces de
linha de comando e web local.

**Fora do escopo:** síntese em tempo real; uso comercial; operação
multiusuário ou em servidor; controle de emoção; fine-tuning de vozes; idiomas
além dos dois definidos.

### 1.3 Glossário

| Termo | Significado |
|---|---|
| **Zero-shot** | Clonagem sem treinamento: o timbre é extraído da referência a cada síntese |
| **RTF** (fator de tempo real) | Segundos de processamento por segundo de áudio. Abaixo de 1,0 é tempo real |
| **Referência** | Gravação curta que define o timbre a ser imitado |
| **XTTS-v2** | Modelo de TTS multilíngue da Coqui, motor deste sistema |
| **CPML** | Coqui Public Model License — licença do XTTS-v2, proíbe uso comercial |
| **Quantização dinâmica** | Conversão dos pesos para int8 em tempo de execução, para ganho de velocidade |

---

## 2. Requisitos

### 2.1 Funcionais

| ID | Requisito | Situação |
|---|---|---|
| RF-01 | Aprender uma voz a partir de um trecho de áudio | Atendido — 6 a 30 s |
| RF-02 | Sintetizar texto arbitrário na voz aprendida | Atendido |
| RF-03 | Suportar pt-BR e en-US | Atendido |
| RF-04 | Persistir vozes entre execuções | Atendido — `vozes/*.wav` |
| RF-05 | Aceitar WAV, MP3 e FLAC como referência | Atendido — conversão automática |
| RF-06 | Controlar a velocidade da fala | Atendido — 0,6 a 1,4 |
| RF-07 | Processar textos longos sem falhar | Atendido — quebra por frases |
| RF-08 | Reportar o tempo de geração | Atendido — `Resultado.fator_tempo_real` |

### 2.2 Não funcionais

| ID | Requisito | Situação |
|---|---|---|
| RNF-01 | **Custo financeiro zero** | Atendido — todo o stack é gratuito |
| RNF-02 | **Operação offline** | Atendido — rede só no download inicial dos pesos |
| RNF-03 | **Sem GPU** | Atendido — PyTorch CPU-only |
| RNF-04 | Rodar sem travar em 31 GB de RAM | Atendido — pico ~4 GB |
| RNF-05 | "Sem demorar muito" | **Parcial** — 3 a 4x o tempo real; ver §6 |
| RNF-06 | Não expor dados na rede | Atendido — servidor apenas em `127.0.0.1` |
| RNF-07 | Dados de voz fora do versionamento | Atendido — `.gitignore` |

O RNF-05 é o único não plenamente atendido, e a limitação é do hardware, não do
desenho: sem GPU, nenhum modelo com qualidade de clonagem alcança tempo real, e
os que alcançam (Piper, Kokoro) não clonam voz. A mitigação foi extrair o máximo
da CPU disponível (§6) e escolher interfaces que amortizem o custo fixo.

### 2.3 Restrições

- Hardware-alvo: Intel i7-8565U, 4 cores físicos, 31 GB de RAM, sem GPU NVIDIA.
- Python 3.12, Linux.
- Licença CPML: uso não comercial.

---

## 3. Visão arquitetural

Arquitetura em três camadas, com o núcleo isolado das interfaces:

```
Interfaces      falar.py (CLI)        web.py (Gradio, localhost)
                        \                  /
Núcleo                   vozclone.py — regra, validação, orquestração
                                 |
Infraestrutura      audio_io.py → coqui-tts/XTTS-v2 → PyTorch CPU
```

O princípio que organiza o desenho: **as interfaces não contêm regra de
negócio**. Validação de idioma, restrições de duração, normalização de áudio,
gestão do ciclo de vida do modelo e medição de desempenho vivem exclusivamente
no núcleo. Uma terceira interface (API HTTP, plugin, bot) se conectaria sem
alterar nada abaixo.

Os diagramas completos estão no [modelo C4](c4/README.md).

### 3.1 Módulos

| Arquivo | Responsabilidade | Linhas |
|---|---|---|
| `vozclone.py` | Núcleo: cadastro, síntese, gestão do modelo, tuning de CPU | ~185 |
| `audio_io.py` | Patch de IO de áudio sobre o torchaudio | ~55 |
| `falar.py` | CLI com três subcomandos | ~85 |
| `web.py` | Interface Gradio | ~75 |

---

## 4. Desenho detalhado

### 4.1 Bootstrap de ambiente

Executado na importação de `vozclone.py`, em ordem obrigatória:

1. `COQUI_TOS_AGREED=1` — aceite da CPML, exigido pelo `coqui-tts`.
2. `audio_io.aplicar()` — substitui o IO do torchaudio **antes** de qualquer
   import de `TTS`.
3. `torch.set_num_threads(cores_físicos)` — ver §6.

A ordem não é estilística. O passo 2 precisa preceder o import de `TTS`, porque
o XTTS resolve `torchaudio.load` no momento do uso, mas o carregamento das
bibliotecas compartilhadas do torchcodec acontece no import. Um chamador que
importe `TTS` diretamente, antes de `vozclone`, reintroduz a falha.

Este acoplamento é a principal fragilidade do desenho e está registrado no
[ADR-0003](adr/0003-io-audio-via-soundfile.md).

### 4.2 Modelo de dados

Não há banco. O estado persistente é o próprio filesystem:

| Local | Conteúdo | Formato |
|---|---|---|
| `vozes/<nome>.wav` | Referência de timbre | WAV mono, 22.050 Hz, PCM 16 bits, pico 0,95 |
| `saida/*.wav` | Áudio gerado | WAV 24.000 Hz (saída nativa do XTTS) |
| `~/.local/share/tts/` | Pesos do modelo | 1,8 GB, imutável após o download |

O identificador de uma voz é o nome do arquivo. `listar_vozes()` é um `glob`.

O único objeto em memória com estrutura é o `Resultado`:

```python
@dataclass
class Resultado:
    caminho: Path
    duracao_audio: float
    tempo_geracao: float

    @property
    def fator_tempo_real(self) -> float: ...
```

Expor o `fator_tempo_real` em toda síntese foi deliberado: num sistema cujo
ponto fraco conhecido é a velocidade, a medição precisa estar visível em vez de
escondida em um benchmark.

### 4.3 Cadastro de vozes

`cadastrar_voz(nome, audio_origem)` executa, nesta ordem:

1. `librosa.load(sr=22050, mono=True)` — resolve decodificação, conversão para
   mono e reamostragem numa chamada. Cobre WAV, MP3 e FLAC via `libsndfile`.
2. **Validação de duração.** Abaixo de 6 s levanta `ValueError`: referências
   curtas produzem timbre instável. Acima de 30 s o excesso é **cortado**, não
   recusado — o ganho de similaridade satura e o encoding só ficaria mais lento.
   A assimetria é intencional: falta de dado é erro, excesso é desperdício.
3. **Normalização de pico** em 0,95. Referências gravadas com volume baixo
   degradam a extração de timbre.
4. Grava em `vozes/<nome>.wav` como PCM 16 bits.

A conversão acontece uma única vez, no cadastro. O caminho de síntese nunca
reprocessa formato.

### 4.4 Gestão do modelo

`carregar_modelo(rapido=False)` implementa um singleton por processo, guardado
em `_modelo`. O custo de carga (~24 s) é pago uma vez, o que define a diferença
de experiência entre CLI e web ([ADR-0007](adr/0007-interfaces-cli-e-web.md)).

Com `rapido=True`, aplica quantização dinâmica int8 nas camadas `Linear` do GPT
autoregressivo, protegida pela flag `_quantizado` para não reaplicar.

**Limitação conhecida:** a quantização é irreversível dentro do processo. Na
interface web, desmarcar o checkbox após uma geração rápida não restaura o
modelo em precisão plena — seria necessário recarregar, a 24 s por alternância.
Documentado no [ADR-0006](adr/0006-quantizacao-int8-opcional.md).

### 4.5 Síntese

`sintetizar(texto, voz, idioma, saida, velocidade, rapido)`:

1. Valida o idioma contra `IDIOMAS` e rejeita texto vazio.
2. Resolve a referência; se a voz não existe, o erro **lista as disponíveis** —
   erros de digitação em nome de voz são o engano mais provável no uso diário.
3. Define a saída padrão como `saida/<voz>-<idioma>-<timestamp>.wav`, o que
   evita sobrescrita acidental entre gerações.
4. Chama `tts_to_file` com `split_sentences=True`. **Não é opcional em CPU**:
   sem a quebra, textos longos consomem memória de forma insustentável.
5. Mede com `time.perf_counter()` e devolve o `Resultado`.

### 4.6 Tratamento de erros

O núcleo levanta apenas `ValueError` (entrada inválida) e `FileNotFoundError`
(recurso ausente). Ambas as interfaces capturam esse par e o traduzem: a CLI
imprime em `stderr` e sai com código 1; a web devolve a mensagem no campo de
status, sem derrubar o servidor.

Exceções fora desse par são falhas não previstas e propagam com o traceback
completo — comportamento desejado para diagnóstico.

---

## 5. Interfaces

### 5.1 API do núcleo

```python
listar_vozes() -> list[str]
caminho_voz(nome: str) -> Path
duracao(caminho: str | Path) -> float
cadastrar_voz(nome: str, audio_origem: str | Path) -> Path
carregar_modelo(rapido: bool = False)
sintetizar(texto, voz, idioma="pt-br", saida=None,
           velocidade=1.0, rapido=False) -> Resultado
```

### 5.2 CLI

```
falar.py cadastrar <nome> <audio>
falar.py vozes
falar.py falar <voz> [texto] [-f arquivo] [-i pt-br|en-us]
                     [-o saida.wav] [-v velocidade] [-r]
```

Códigos de saída: `0` sucesso, `1` erro tratado, `2` erro de argumentos
(argparse).

### 5.3 Web

Gradio em `127.0.0.1:7860`, duas abas (cadastro e síntese). O bind em localhost
é explícito e `share=True` não é usado — expor por túnel público um serviço que
processa dado biométrico contrariaria o requisito de operação local.

---

## 6. Desempenho

### 6.1 Medições

Intel i7-8565U, 4 cores, sem GPU, governor `powersave`:

| Cenário | Áudio | Geração | RTF |
|---|---|---|---|
| Carga do modelo | — | 24,0 s | — |
| Frase curta, pt-BR | 4,7 s | 23,7 s | 5,05x |
| Frase curta, en-US | 5,0 s | 18,3 s | 3,65x |
| Parágrafo, pt-BR | 14,2 s | 56,4 s | 3,98x |
| Frase curta, int8 | 4,0 s | 13,2 s | 3,31x |

### 6.2 Otimizações aplicadas

**Threads fixadas nos cores físicos.** Contraintuitivo e medido: 8 threads
lógicas levaram 54,3 s contra 21,4 s com 4 — **2,5x mais lento**. A causa provável
é contenção por unidades AVX e cache entre threads irmãs do mesmo core. Detectado
via `/sys/.../thread_siblings_list` ([ADR-0005](adr/0005-threads-cores-fisicos.md)).

**Quantização int8 opcional.** 21,4 s → 17,1 s, ~20% de ganho. Desligada por
padrão porque a perda de fidelidade não foi avaliada auditivamente, e fidelidade
de timbre é justamente o propósito do sistema ([ADR-0006](adr/0006-quantizacao-int8-opcional.md)).

**Modelo residente na interface web.** Amortiza os 24 s de carga.

### 6.3 Não explorado

- **Governor `performance`** — a CPU está em `powersave`; a mudança exige sudo e
  não foi aplicada. Ganho esperado relevante.
- **Cache do latente do falante** — o encoding da referência é refeito a cada
  síntese. Cachear por voz beneficiaria lotes.
- **ONNX Runtime / OpenVINO** — poderia superar o PyTorch em CPU Intel, ao custo
  de uma etapa de conversão e de risco de divergência numérica.

### 6.4 Perfil de recursos

Pico de ~4 GB de RAM durante a síntese, contra 31 GB disponíveis. Disco: 1,7 GB
de ambiente virtual e 1,8 GB de pesos.

---

## 7. Segurança da informação

### 7.1 Classificação dos dados

| Dado | Classificação | Tratamento |
|---|---|---|
| Referências de voz (`vozes/`) | **Dado pessoal sensível (biométrico)** | Local, fora do versionamento |
| Áudios gerados (`saida/`) | Sensível por derivação | Local, fora do versionamento |
| Texto de entrada | Conforme o conteúdo | Não persistido pelo sistema |
| Pesos do modelo | Público | Cache local |

### 7.2 Controles implementados

- **Nenhuma transmissão de dados.** Após o download dos pesos, o sistema não faz
  requisições de rede. Áudio de voz nunca sai da máquina.
- **Bind restrito a `127.0.0.1`**, sem compartilhamento remoto do Gradio.
- **`.gitignore`** cobre `vozes/`, `saida/` e `.venv/`.
- **Exclusão trivial**: apagar o dado biométrico é apagar um arquivo — relevante
  para atender pedidos de exclusão sob a LGPD.

### 7.3 Riscos aceitos

| Risco | Avaliação |
|---|---|
| **Sem cifragem em repouso** | Aceito para uso pessoal em máquina de trabalho. Obrigatório revisar em cenário multiusuário |
| **Sem registro de consentimento** | O sistema não guarda quem autorizou a clonagem nem por quanto tempo. É controle de processo, não de sistema |
| **Nomes de voz não sanitizados** | Um nome contendo `../` escreveria fora de `vozes/`. Não explorável por rede, pois a interface é local e monousuário |
| **Uso indevido para personificação** | Risco inerente à tecnologia. Mitigado por documentação, não por controle técnico |

### 7.4 Uso responsável

Clonagem de voz exige **consentimento explícito** da pessoa cuja voz é clonada.
O sistema não deve ser usado para imitar terceiros sem autorização nem para
produzir conteúdo que se passe por outra pessoa.

Ao compartilhar áudios gerados ou referências de voz com terceiros, lembre que
áudio de voz é dado biométrico e merece o mesmo cuidado de qualquer dado
pessoal.

---

## 8. Dependências e riscos técnicos

### 8.1 Principais dependências

| Pacote | Versão | Papel | Observação |
|---|---|---|---|
| `torch` | 2.13.0+cpu | Runtime de inferência | Build CPU-only deliberado |
| `coqui-tts[codec]` | 0.27.5 | XTTS-v2 | Fork comunitário; o original foi abandonado |
| `transformers` | <5 (4.57.6) | Backbone do GPT | **Pin obrigatório** |
| `librosa` / `soundfile` | 1.0.0 / 0.14.0 | IO de áudio | Substituem o torchaudio |
| `gradio` | — | Interface web | Só a interface depende |

### 8.2 Incompatibilidades resolvidas

Três quebras reais do ecossistema, encontradas na montagem:

1. **`transformers` 5.x removeu `isin_mps_friendly`**, usado pelo backbone
   Tortoise do XTTS. Resolvido com `transformers<5` ([ADR-0004](adr/0004-fixar-transformers-4x.md)).
2. **`torchaudio` 2.9+ delegou o IO ao `torchcodec`**, cujo wheel é compilado
   contra CUDA e não carrega sobre PyTorch CPU-only. Quebrava justamente a
   leitura da voz de referência. Resolvido com `audio_io.py`
   ([ADR-0003](adr/0003-io-audio-via-soundfile.md)).
3. **`coqui-tts` passou a exigir o extra `[codec]`** com PyTorch 2.9+.

### 8.3 Riscos de manutenção

| Risco | Impacto | Mitigação |
|---|---|---|
| Abandono do fork `coqui-tts` | Alto | Ambiente fixado e funcional; migração para Chatterbox é o plano B |
| Remoção da API de quantização do PyTorch | Baixo | O modo rápido é opcional; o padrão não depende dele |
| Reinstalação sem o pin de `transformers` | Médio | Documentado no README, no manual e em ADR |
| Mudança interna do XTTS no uso do `torchaudio` | Médio | Teste de fumaça: cadastrar uma voz e sintetizar |

---

## 9. Evolução

### 9.1 Se o uso deixar de ser pessoal

A CPML proíbe uso comercial. Tornar o projeto um produto exige **trocar o
motor** — o candidato é o Chatterbox Multilingual (MIT), que tem português e
aceita uso comercial, ao custo de ser mais lento em CPU. Como o núcleo isola o
motor, a troca fica confinada a `carregar_modelo` e `sintetizar`.

### 9.2 Melhorias mapeadas

Em ordem de relação custo-benefício:

1. **Cache do latente do falante** — ganho direto em lotes com a mesma voz.
2. **Sanitizar nomes de voz** — fecha a aspereza de travessia de caminho (§7.3).
3. **Recarregar o modelo ao alternar o modo rápido** — corrige a
   irreversibilidade da quantização (§4.4).
4. **Ampliar os idiomas** — o XTTS-v2 suporta 17; expor mais é ampliar o dicionário
   `IDIOMAS`.
5. **Testes automatizados** — não há suíte; a validação foi manual, de ponta a
   ponta. Um teste de fumaça cobrindo cadastro e síntese protegeria contra as
   quebras de dependência descritas em §8.2.

### 9.3 O que exigiria redesenho

Síntese em tempo real, operação multiusuário, execução em servidor compartilhado
ou controle de emoção não são extensões deste desenho — implicariam outro motor,
outro modelo de segurança e outro perfil de hardware.

---

## 10. Referências

- [Manual de uso](MANUAL.md)
- [Architecture Decision Records](adr/)
- [Modelo C4](c4/README.md)
- [XTTS-v2 no Hugging Face](https://huggingface.co/coqui/XTTS-v2)
- [coqui-tts (fork mantido)](https://github.com/idiap/coqui-ai-TTS)
- [C4 model](https://c4model.com/)
