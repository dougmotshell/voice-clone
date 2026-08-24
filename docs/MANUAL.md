# Manual do Clonador de Voz Local

**Versão 1.2** — inclui instalação e desinstalação por script, execução em
contêiner e suporte a Linux, macOS e Windows.

Manual de operação do sistema de clonagem de voz. Para as decisões de
arquitetura, veja o [SDD](SDD.md), os [ADRs](adr/) e o [modelo C4](c4/).

---

## 1. O que o sistema faz

A partir de **6 a 30 segundos** de fala gravada, o sistema aprende o timbre de
uma voz e passa a sintetizar **qualquer texto** naquela voz, em **português do
Brasil** e **inglês americano**.

Roda **inteiramente na sua máquina**, sem GPU, sem custo e sem internet — o
único acesso à rede é o download inicial dos pesos do modelo (1,8 GB), feito uma
única vez.

Não há treinamento: a clonagem é *zero-shot*, ou seja, o modelo extrai as
características da voz na hora, a cada síntese.

---

## 2. Antes de começar

### Requisitos

- **Python 3.12** (3.10 a 3.13 têm wheels; 3.12 é a versão validada)
- ~3,5 GB de disco (1,7 GB de ambiente + 1,8 GB de pesos)
- 4 GB de RAM livres durante a execução
- Nenhuma GPU necessária

Plataformas suportadas:

| Sistema | Situação |
|---|---|
| **Linux** x86-64 ou ARM64 | Validado, e é onde os números de desempenho foram medidos |
| **Windows** 10/11 x86-64 | Suportado; instalação resolvida e verificada, síntese não medida |
| **macOS 14+** Apple Silicon | Suportado; o PyTorch não publica mais wheels para Mac Intel |

### Instalação

São três caminhos. O primeiro serve para usar o sistema; o segundo, para mexer
nele; o terceiro dispensa montar ambiente Python nenhum.

Em todos, o [uv](https://docs.astral.sh/uv/) é quem instala as dependências. Ele
não é uma preferência: o `requirements.txt` carrega fixações que **não são
opcionais** — o wheel CPU-only do PyTorch no Linux e as versões compatíveis — e
o `uv.toml`, a estratégia de índice que elas pressupõem. Instalar à mão, ou com
`pip`, tem chance alta de trazer 2,5 GB de CUDA inútil ou o wheel errado do
`torchcodec` (ver [ADR-0010](adr/0010-portabilidade-tres-plataformas.md)).

#### a) Pelo script de instalação — para usar

Não clona o repositório: baixa os sete arquivos que a execução exige, monta o
ambiente, cria os atalhos e verifica o resultado
([ADR-0011](adr/0011-instalacao-por-script.md)).

Prefira ler antes de executar:

```bash
# Linux e macOS
curl -fsSLO https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.sh
less install.sh          # leia
sh install.sh
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.ps1 -OutFile install.ps1
notepad install.ps1      # leia
.\install.ps1
```

Se preferir o atalho, em uma linha:

```bash
curl -fsSL https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.sh | sh
```

```powershell
irm https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.ps1 | iex
```

Vale saber o que se aceita aí: essa forma executa código que você não leu, e
`main` é um ref móvel. Para amarrar a instalação a um ponto exato da história,
passe `--ref <sha>`.

Onde as coisas ficam:

| | Linux e macOS | Windows |
|---|---|---|
| Programa e ambiente | `~/.local/share/voice-clone` | `%LOCALAPPDATA%\voice-clone` |
| Vozes e áudios | `…/voice-clone/vozes` e `…/saida` | idem |
| Atalhos | `~/.local/bin/voice-clone`, `…-web` | `…\voice-clone\bin\voice-clone.cmd` |
| Pesos do XTTS-v2 | `~/.local/share/tts` | `%LOCALAPPDATA%\tts` |

Depois disso, os comandos funcionam de qualquer diretório:

```bash
voice-clone checar
voice-clone cadastrar minhavoz ~/audios/minha-voz.wav
voice-clone falar minhavoz "Olá, mundo."
voice-clone-web
```

Se o diretório dos atalhos não estiver no `PATH`, o instalador avisa e mostra a
linha a acrescentar — ele não edita o seu `rc` nem o seu `PATH` sem pedir. No
Windows, `-AdicionarAoPath` autoriza essa edição.

Opções úteis (no PowerShell, os mesmos nomes em `-CamelCase`):

| Opção | Efeito |
|---|---|
| `--prefixo DIR` | instala em outro lugar |
| `--bin DIR` | cria os atalhos em outro lugar |
| `--ref REF` | branch, tag ou commit a baixar |
| `--local DIR` | instala de uma árvore em disco, sem rede |
| `--instalar-uv` | instala o `uv` se ele não estiver disponível |
| `--sem-verificar` | não roda `checar` no fim |
| `--ajuda` | a lista completa |

Reinstalar por cima é seguro: `vozes/` e `saida/` nunca são tocados.

#### b) A partir de um clone — para desenvolver

```bash
# Linux e macOS
uv venv --python 3.12 .venv
VIRTUAL_ENV=.venv uv pip install -r requirements.txt

# Windows (PowerShell)
uv venv --python 3.12 .venv
$env:VIRTUAL_ENV=".venv"; uv pip install -r requirements.txt
```

Rodando de dentro do clone, o instalador também serve — ele usa a árvore local
em vez da rede, e dá os atalhos de brinde:

```bash
sh scripts/install.sh
```

#### c) Verifique, sempre

```bash
voice-clone checar
# no clone: .venv/bin/python falar.py checar
# Windows, no clone: .venv\Scripts\python falar.py checar
```

Todas as linhas devem sair `ok`. Se alguma sair `FALHA`, a própria saída diz o
que fazer; a seção 8 detalha cada caso. Pelo script de instalação, essa
verificação já acontece no fim.

### Sem instalar nada: Docker

Se preferir não montar o ambiente Python, a seção 6 mostra como rodar tudo em
contêiner com um comando.

### Preparando o áudio de referência

A qualidade da clonagem depende mais do áudio de referência do que de qualquer
ajuste no sistema. Um bom material de referência tem:

| Característica | Recomendação |
|---|---|
| Duração | 15–20 s é o ponto ideal (mínimo 6 s, máximo 30 s) |
| Conteúdo | Fala contínua e natural, em frases completas |
| Ruído | Nenhum. Sem música, sem eco, sem outras vozes |
| Formato | WAV, MP3 ou FLAC — a conversão é automática |
| Gravação | Ambiente fechado, microfone a uma distância constante |

O que **degrada** o resultado: sussurro, grito, fala muito rápida, cortes
abruptos, compressão agressiva de MP3, e trechos com silêncio longo.

O sistema recusa áudios com menos de 6 s e corta automaticamente o que passar de
30 s. Ele também converte tudo para mono a 22.050 Hz e normaliza o volume, então
não é preciso preparar o arquivo manualmente.

---

## 3. Uso pela interface web (recomendado)

A interface web é mais confortável para uso repetido, porque mantém o modelo
carregado na memória entre as gerações — você paga os ~24 s de carga uma vez só.

```bash
voice-clone-web                  # instalado pelo script
```

```bash
cd voice-clone                   # a partir de um clone
.venv/bin/python web.py          # Windows: .venv\Scripts\python web.py
```

Abra `http://127.0.0.1:7860` no navegador. O servidor escuta **apenas em
localhost**: não fica exposto na rede.

A interface tem paridade com a CLI: tudo que `falar.py` faz, ela faz.

**Aba "1. Vozes"** — à esquerda, o cadastro: dê um nome à voz, grave pelo
microfone ou envie um arquivo, e clique em *Cadastrar voz*. À direita, a lista
das vozes já cadastradas com a duração de cada referência — equivale a
`falar.py vozes`.

**Aba "2. Falar"** — selecione a voz, escreva o texto **ou** envie um `.txt`
(que tem precedência, como o `-f` da CLI), escolha idioma, velocidade e, se
quiser, o nome do arquivo de saída. *Gerar áudio* mostra o player, um botão de
download e o tempo que a geração levou. *Pré-carregar modelo* paga os ~24 s de
carga na hora que você escolher, em vez de na primeira geração.

**Aba "3. Ambiente"** — equivale a `falar.py checar`: confere as correções de
compatibilidade e o ambiente de execução. É o primeiro lugar a olhar quando algo
para de funcionar.

Para encerrar, `Ctrl+C` no terminal.

---

## 4. Uso pela linha de comando

Útil para automação, lotes e scripts. Cada execução recarrega o modelo (~24 s),
então prefira gerar textos longos de uma vez em vez de muitas chamadas curtas.

### Cadastrar uma voz

```bash
.venv/bin/python falar.py cadastrar douglas ~/audios/minha-voz.wav
```

O nome (`douglas`) é como você vai se referir à voz depois. Cadastrar de novo
com o mesmo nome substitui a referência anterior.

No Windows, troque `.venv/bin/python` por `.venv\Scripts\python` em todos os
exemplos abaixo. Instalado pelo script, o comando é `voice-clone` no lugar de
`.venv/bin/python falar.py`, e funciona de qualquer diretório:

```bash
voice-clone cadastrar douglas ~/audios/minha-voz.wav
```

### Listar vozes

```bash
.venv/bin/python falar.py vozes
```

### Verificar o ambiente

```bash
.venv/bin/python falar.py checar
```

Confere, no ambiente real e não em metadados, que as correções de
compatibilidade estão ativas, que o PyTorch é CPU-only, que os wheels certos
foram instalados e que o `TTS` sobe. É o primeiro comando a rodar depois de
instalar e depois de qualquer atualização de dependência.

### Gerar áudio

```bash
# português (padrão)
.venv/bin/python falar.py falar douglas "Olá, este é um teste."

# inglês
.venv/bin/python falar.py falar douglas "Hello, this is a test." -i en-us

# a partir de um arquivo de texto, com saída definida
.venv/bin/python falar.py falar douglas -f roteiro.txt -o saida/narracao.wav

# um pouco mais rápido na fala, e com o modo rápido de síntese
.venv/bin/python falar.py falar douglas "Texto aqui." -v 1.1 -r
```

### Opções de `falar`

| Opção | Efeito |
|---|---|
| `-i`, `--idioma` | `pt-br` (padrão) ou `en-us` |
| `-f`, `--arquivo` | Lê o texto de um `.txt` em vez do argumento |
| `-o`, `--saida` | Caminho do WAV gerado (padrão: `saida/<voz>-<idioma>-<timestamp>.wav`) |
| `-v`, `--velocidade` | 0.6 a 1.4 — ritmo da fala (padrão 1.0) |
| `-r`, `--rapido` | Quantização int8: ~20% mais rápido, leve perda de fidelidade |

Nomes de voz e de arquivo de saída passam por validação: os caracteres que o
Windows recusa (`< > : " / \ | ? *`), os nomes reservados (`CON`, `NUL`,
`COM1`…) e ponto ou espaço no fim são rejeitados em todas as plataformas, para
que uma voz cadastrada num sistema tenha nome válido nos outros.

---

## 5. Uso como biblioteca Python

```python
from vozclone import cadastrar_voz, sintetizar, listar_vozes

cadastrar_voz("douglas", "/caminho/audio.wav")

r = sintetizar("Texto a ser falado.", voz="douglas", idioma="pt-br")
print(r.caminho, r.duracao_audio, r.tempo_geracao, r.fator_tempo_real)
```

Em scripts que geram vários áudios, chame `carregar_modelo()` uma vez no início:
as chamadas seguintes de `sintetizar` reaproveitam o modelo já em memória.

---

## 6. Uso em contêiner

Roda a mesma aplicação sem montar ambiente Python na máquina. Requer Docker com
o plugin Compose.

```bash
docker compose up --build
```

A interface fica em `http://127.0.0.1:7860`. A porta é publicada **apenas em
127.0.0.1**: como na execução local, nada é alcançável de outra máquina.

A CLI usa a mesma imagem:

```bash
docker compose run --rm cli checar
docker compose run --rm cli vozes
docker compose run --rm cli cadastrar douglas /app/vozes/origem.wav
docker compose run --rm cli falar douglas "Olá, mundo."
```

### O que fica onde

| Caminho | Onde vive | Por quê |
|---|---|---|
| `./vozes` | Host, montado em `/app/vozes` | São os seus dados; não devem morar na imagem |
| `./saida` | Host, montado em `/app/saida` | Os áudios gerados ficam acessíveis fora do contêiner |
| Volume `modelos` | Volume nomeado, em `/modelos` | Os 1,8 GB de pesos sobrevivem a `down` e a rebuild |

O primeiro `up` baixa os pesos (1,8 GB) e leva alguns minutos. Do segundo em
diante, o volume já os tem.

### Notas

- **A imagem não embute o modelo.** Isso a mantém em ~1,5 GB em vez de ~3,3 GB, e
  evita distribuir pesos sob CPML.
- **Sem CUDA e sem FFmpeg.** A imagem é CPU-only por construção, e o `soundfile`
  traz o `libsndfile` no próprio wheel (ver [ADR-0003](adr/0003-io-audio-via-soundfile.md)).
- **UID/GID 1000** dentro do contêiner, para que os arquivos criados em `vozes/`
  e `saida/` continuem seus no host. Se o seu usuário tem outro UID, ajuste no
  `Dockerfile`.
- **Threads:** `OMP_NUM_THREADS` no `docker-compose.yml` está em 4. Ajuste para o
  número de **cores físicos** da sua máquina — não os lógicos (seção 7).
- Encerre com `Ctrl+C` e, se quiser remover os contêineres, `docker compose down`.
  Os pesos ficam: só `docker compose down -v` apaga o volume.

---

## 7. O que esperar de desempenho

Medido em Intel i7-8565U (4 cores, sem GPU), governor `powersave`, Linux. **É a
única máquina onde a síntese foi cronometrada** — em macOS e Windows a
instalação foi verificada, o desempenho não.

| Tarefa | Tempo |
|---|---|
| Carga do modelo (uma vez por processo) | ~24 s |
| Frase curta (~5 s de áudio) | ~21 s — ou ~17 s com `-r` |
| Parágrafo (~14 s de áudio) | ~56 s |

Na prática: **3 a 4 segundos de processamento por segundo de áudio gerado**.

Isso **não é tempo real** e não há como torná-lo tempo real sem GPU. O sistema
foi feito para geração em lote — narração, roteiros, testes — e não para
conversação ao vivo.

### Como acelerar

1. **Use a interface web** para trabalho repetido: economiza os 24 s de carga
   a cada geração.
2. **Ative o modo rápido** (`-r` ou o checkbox) se a perda de fidelidade for
   aceitável para o seu caso. Compare ouvindo os dois antes de decidir.
3. **Mude o governor da CPU** para `performance` (requer sudo):
   ```bash
   sudo cpupower frequency-set -g performance
   ```
4. **Não aumente o número de threads.** O sistema já detecta os cores físicos e
   se fixa neles. Usar as threads lógicas mede 2,5x **mais lento** neste modelo.
   Em contêiner, o mesmo vale para `OMP_NUM_THREADS` no `docker-compose.yml`.

---

## 8. Solução de problemas

**Comece sempre por `falar.py checar`.** Ele distingue os modos de falha
conhecidos e diz qual é o seu, em vez de deixar você adivinhar a partir de um
traceback. Na interface web, a aba "3. Ambiente" faz o mesmo.

### Erros de uso

**"Referência de X s é curta demais"** — o áudio tem menos de 6 s. Grave mais.

**"Voz 'nome' não existe"** — rode `falar.py vozes` para ver os nomes
cadastrados. O nome diferencia maiúsculas de minúsculas.

**A voz gerada não se parece com a original** — quase sempre é o áudio de
referência. Regrave com 15–20 s de fala contínua e limpa. Se estiver usando o
modo rápido, teste sem ele.

**A pronúncia sai errada em nomes próprios ou siglas** — escreva foneticamente
no texto de entrada (`"A P I"` em vez de `"API"`). O modelo não tem dicionário
de exceções.

**Parece travado em textos longos** — não está: o modelo processa frase a frase.
Um parágrafo leva perto de um minuto. Acompanhe pelo terminal.

**"O nome não pode conter < > : " / \ | ? *"** ou **"é um nome reservado pelo
Windows"** — o nome da voz vira nome de arquivo e precisa ser válido nas três
plataformas. Escolha outro. Os nomes de dispositivo do Windows (`CON`, `NUL`,
`COM1`…) são recusados também com extensão, porque `CON.wav` lá continua sendo o
console e não um arquivo.

**"O nome tem N caracteres; o limite é 128"** — rótulo de voz é curto. O limite
evita que o estouro apareça só na gravação, como erro do sistema operacional.

### Erros de ambiente

**`checar` diz `torchcodec ... ligado a CUDA`** — o ambiente foi montado com o
wheel do PyPI em vez do `+cpu`. A síntese continua funcionando, porque o IO de
áudio é feito por `soundfile`, mas conserte a origem:

```bash
VIRTUAL_ENV=.venv uv pip install -r requirements.txt
```

**`OSError: Could not load this library: libtorchcodec_image.so`** — a mesma
causa acima, agora fatal: algum código importou `torchcodec` diretamente, ou
importou `TTS` antes de `vozclone`. Sempre importe `vozclone` primeiro; ele
aplica as correções antes de tocar no `TTS`
(ver [ADR-0003](adr/0003-io-audio-via-soundfile.md)).

**`ImportError: cannot import name 'isin_mps_friendly'`** — o `TTS` foi
importado sem as correções, novamente por ordem de import. O `compat.py` repõe
esse símbolo, o que faz o projeto funcionar tanto no `transformers` 4.x quanto
no 5.x; **não** é mais necessário fixar `transformers<5`
(ver [ADR-0009](adr/0009-transformers-5-por-reposicao-de-simbolo.md)).

**`checar` diz que o `transformers` está fora das versões validadas** — é aviso,
não erro: a síntese pode funcionar. As versões testadas de ponta a ponta estão
em `compat.TRANSFORMERS_VALIDADO`. Se algo quebrar, volte para uma delas.

**`checar` diz `build CUDA ... inesperado`** — o PyTorch instalado é o de GPU.
Numa máquina sem GPU ele só ocupa disco; reinstale pelo `requirements.txt`
(ver [ADR-0002](adr/0002-pytorch-cpu-only.md)).

**Acentos saem corrompidos ao redirecionar a saída no Windows** — a CLI força
UTF-8 na saída. Se ainda ocorrer, defina `PYTHONIOENCODING=utf-8`.

**"Modo rápido indisponível nesta CPU"** — o backend de quantização int8 não
existe para essa arquitetura. A síntese continua em float32, apenas sem o ganho
de ~20%.

**No macOS, `uv pip install` não acha wheel do PyTorch** — o PyTorch não publica
mais wheels para Mac Intel, e os de 2.12+ exigem macOS 14. Num Mac Intel é
preciso recuar as versões no `requirements.txt`
(ver [ADR-0010](adr/0010-portabilidade-tres-plataformas.md)).

### Docker

**O primeiro `up` parece parado** — está baixando 1,8 GB de pesos. Acompanhe com
`docker compose logs -f`.

**Os pesos são baixados de novo a cada `up`** — o volume `modelos` foi removido,
provavelmente por um `docker compose down -v`.

**Permissão negada em `vozes/` ou `saida/`** — o contêiner roda como UID 1000. Se
o seu usuário tem outro UID (`id -u`), ajuste no `Dockerfile`.

### Disco

**Sem espaço em disco** — os pesos ficam em `~/.local/share/tts` no Linux,
`~/Library/Application Support/tts` no macOS e `%LOCALAPPDATA%\tts` no Windows
(1,8 GB); em contêiner, no volume `modelos`. O ambiente virtual ocupa ~1,7 GB.
Os áudios gerados se acumulam em `saida/` e podem ser apagados à vontade. A
variável `TTS_HOME` move o cache dos pesos para outro lugar. Para recuperar os
1,8 GB dos pesos de uma vez, veja a seção 9.

---

## 9. Desinstalação

O instalador deixa uma cópia do desinstalador dentro do prefixo, então remover
não depende de rede nem de ter o repositório em disco.

```bash
# Linux e macOS
~/.local/share/voice-clone/uninstall.sh
```

```powershell
# Windows
& "$env:LOCALAPPDATA\voice-clone\uninstall.ps1"
```

**O padrão remove o programa e preserva os seus dados.** Isso é deliberado:
`vozes/` guarda referências de voz, que são dado biométrico, e os pesos são
1,8 GB que ninguém quer baixar de novo por acidente
([ADR-0011](adr/0011-instalacao-por-script.md)).

Antes de qualquer coisa, veja a lista do que seria removido:

```bash
~/.local/share/voice-clone/uninstall.sh --simular
```

| Opção | Efeito |
|---|---|
| *(nenhuma)* | remove o ambiente, o código e os atalhos |
| `--remover-dados` | remove também `vozes/` e `saida/` — pede confirmação |
| `--remover-modelos` | remove o cache de pesos do XTTS-v2 (~1,8 GB) |
| `--tudo` | as duas acima juntas |
| `--simular` | lista o que seria removido, sem remover |
| `--prefixo DIR` | se você instalou em outro lugar |
| `--sim` | não pergunta nada; obrigatório sem terminal interativo |

No PowerShell, os mesmos nomes em `-CamelCase`: `-RemoverDados`,
`-RemoverModelos`, `-Tudo`, `-Simular`, `-Prefixo`, `-Sim`.

Apagar as vozes é irreversível, e o desinstalador exige confirmação digitada
para isso. Se não vai mais usar o sistema, apagar é o certo: referência de voz
guardada sem necessidade é dado biométrico exposto sem motivo.

**Instalou a partir de um clone, sem o script?** Aí não há o que desinstalar
além do que você criou: apague `.venv/` e o diretório do clone, e apague o cache
dos pesos à mão (`~/.local/share/tts` no Linux, `~/Library/Application Support/tts`
no macOS, `%LOCALAPPDATA%\tts` no Windows). Em contêiner, `docker compose down -v`
remove o volume `modelos`, e `docker rmi voice-clone:local` a imagem.

---

## 10. Limites conhecidos

- **Dois idiomas apenas** nesta configuração (pt-BR e en-US), embora o XTTS-v2
  suporte 17. Foi uma restrição de escopo, não do modelo.
- **Sem controle de emoção** — o tom vem do áudio de referência. Uma referência
  neutra produz fala neutra.
- **Sem streaming** — o áudio só fica disponível quando a geração termina.
- **Uma voz por síntese** — não há diálogo entre vozes diferentes num mesmo
  arquivo.
- **Não determinístico** — o mesmo texto gera áudios ligeiramente diferentes a
  cada execução.
- **Desempenho medido só em Linux.** Em macOS e Windows a instalação foi
  verificada; a síntese não foi cronometrada.
- **Sem testes automatizados.** A verificação é `falar.py checar` mais uma
  síntese real.

---

## 11. Uso responsável e segurança da informação

**Consentimento é obrigatório.** Clonar a voz de uma pessoa exige autorização
explícita dela. Não use o sistema para imitar terceiros sem permissão, nem para
produzir conteúdo que se passe por outra pessoa.

**Áudio de voz é dado biométrico.** O conteúdo de `vozes/` deve ser tratado com
o mesmo cuidado de qualquer dado pessoal sensível:

- `vozes/` e `saida/` já estão no `.gitignore` — não versione essas pastas.
- Não envie referências de voz para serviços externos, repositórios
  compartilhados ou canais de chat.
- Remova as referências quando não forem mais necessárias.

**Licença do modelo.** O XTTS-v2 usa a Coqui Public Model License (CPML), que
**proíbe uso comercial**. Esta instalação está configurada para uso pessoal e
experimentação. Para uso comercial seria necessário trocar o motor
(ver [ADR-0001](adr/0001-motor-tts-xtts-v2.md)).

Ao compartilhar áudios gerados ou referências de voz com terceiros, lembre que
áudio de voz é dado biométrico e merece o mesmo cuidado de qualquer dado
pessoal.
