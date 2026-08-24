# Clonador de Voz Local

Sistema de clonagem de voz que roda **100% offline na CPU**, sem custo e sem
enviar áudio para nenhum serviço externo. A partir de 6–30 segundos de fala,
sintetiza qualquer texto naquela voz em **pt-BR** e **en-US**.

Roda em **Linux, macOS e Windows**, direto ou em contêiner.

## Documentação

| Documento | Conteúdo |
|---|---|
| **[Manual de uso](docs/MANUAL.md)** | Instalação, operação, contêiner, preparo do áudio, solução de problemas |
| **[SDD](docs/SDD.md)** | Requisitos, arquitetura, desempenho, segurança |
| **[Modelo C4](docs/c4/README.md)** | Diagramas de contexto, contêiner e componente |
| **[ADRs](docs/adr/)** | As dez decisões de arquitetura e seus porquês |
| **[AGENTS.md](AGENTS.md)** | Contrato para agentes de IA que trabalham neste repositório |

## Como foi escolhido o modelo

O motor é o **XTTS-v2** (Coqui), via o fork mantido `coqui-tts`. A seleção
partiu de três restrições: custo zero, execução sem GPU e suporte simultâneo a
pt-BR e en-US.

| Modelo | Situação |
|---|---|
| **XTTS-v2** | **Escolhido.** pt e en nativos, clonagem com 6s, ~4–6 GB de RAM, roda em CPU |
| Chatterbox Multilingual | Licença MIT (permite uso comercial), mas mais lento em CPU |
| Qwen3-TTS | Apache-2.0 e tem pt-BR, porém exige CUDA — sem inferência em CPU |
| NeuTTS Air | Ideal em performance (748M, GGUF, roda em Raspberry Pi), mas sem pt-BR |
| F5-TTS | Qualidade alta, inviável em CPU (RTF ~37) |
| Piper / Kokoro | Rápidos em CPU, mas não fazem clonagem zero-shot |

## Instalação

Exige o [uv](https://docs.astral.sh/uv/), que é quem resolve os wheels certos.
Toda a configuração está em `requirements.txt` e `uv.toml` — não instale as
dependências à mão.

### Para usar: o script de instalação

Não clona o repositório. Baixa os sete arquivos que a execução exige, monta o
ambiente, cria os atalhos `voice-clone` e `voice-clone-web`, e roda a verificação
no fim ([ADR-0011](docs/adr/0011-instalacao-por-script.md)).

Baixe, leia, execute:

```bash
# Linux e macOS
curl -fsSLO https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.sh
less install.sh
sh install.sh
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.ps1 -OutFile install.ps1
notepad install.ps1
.\install.ps1
```

Ou em uma linha, aceitando executar código que você não leu:

```bash
curl -fsSL https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.sh | sh
```

```powershell
irm https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.ps1 | iex
```

Instala em `~/.local/share/voice-clone` (`%LOCALAPPDATA%\voice-clone` no
Windows), com as vozes e os áudios lá dentro. `--prefixo` muda o destino,
`--ref <sha>` amarra a um commit exato, `--ajuda` lista o resto.

**Para desinstalar**, o script fica no próprio prefixo:

```bash
~/.local/share/voice-clone/uninstall.sh --simular   # veja antes o que sai
~/.local/share/voice-clone/uninstall.sh             # remove o programa
```

Ele **preserva** `vozes/` e `saida/` e os 1,8 GB de pesos por padrão;
`--remover-dados`, `--remover-modelos` e `--tudo` removem, com confirmação.
Detalhes na [seção 9 do manual](docs/MANUAL.md).

### Para desenvolver: a partir de um clone

```bash
# Linux e macOS
uv venv --python 3.12 .venv
VIRTUAL_ENV=.venv uv pip install -r requirements.txt

# Windows (PowerShell)
uv venv --python 3.12 .venv
$env:VIRTUAL_ENV=".venv"; uv pip install -r requirements.txt
```

Confirme o ambiente antes de usar:

```bash
voice-clone checar                   # instalado pelo script
.venv/bin/python falar.py checar     # no clone; Windows: .venv\Scripts\python falar.py checar
```

```
ok   PyTorch CPU-only: torch 2.13.0+cpu
ok   isin_mps_friendly disponível: transformers 4.57.6 (símbolo nativo)
ok   IO de áudio por soundfile: torchaudio 2.11.0+cpu + soundfile 0.14.0
ok   torchcodec carrega: torchcodec 0.16.0+cpu
ok   import TTS: coqui-tts 0.27.5
ok   Threads do PyTorch: 4 de 8 lógicas (cores físicos; ADR-0005)
ok   Plataforma: Linux x86_64, Python 3.12.3
```

Requisitos por plataforma:

| Sistema | Situação |
|---|---|
| **Linux** x86-64 / ARM64 | Validado; é onde o desempenho foi medido |
| **Windows** 10/11 x86-64 | Instalação resolvida e verificada; síntese não medida |
| **macOS 14+** Apple Silicon | Idem. O PyTorch não publica mais wheels para Mac Intel |

## Uso pela linha de comando

```bash
# verificar o ambiente e as correções de compatibilidade
./falar.py checar

# cadastrar uma voz a partir de um áudio (wav, mp3, flac)
./falar.py cadastrar douglas ~/audios/minha-voz.wav

# listar vozes
./falar.py vozes

# gerar áudio
./falar.py falar douglas "Olá, este é um teste de clonagem de voz."
./falar.py falar douglas "Hello, this is a test." -i en-us
./falar.py falar douglas -f roteiro.txt -o saida/narracao.wav -v 1.1
```

Rode com `.venv/bin/python falar.py ...` se o shebang não pegar o venv, e com
`.venv\Scripts\python falar.py ...` no Windows. Instalado pelo script, o comando
é `voice-clone <subcomando>`, de qualquer diretório.

## Interface web

```bash
voice-clone-web            # instalado pelo script
.venv/bin/python web.py    # a partir de um clone
```

Abre em `http://127.0.0.1:7860`, apenas em localhost. Tem **paridade completa
com a CLI**: aba 1 lista e cadastra vozes, aba 2 gera áudio (texto digitado ou
`.txt` enviado, idioma, velocidade, modo rápido, nome de saída, download), aba 3
faz a verificação de ambiente do `checar`.

Como a carga do modelo é fixa em ~24 s, a interface web é bem mais confortável
que a CLI para uso repetido: o modelo fica residente entre as gerações.

## Contêiner

```bash
docker compose up --build              # web em http://127.0.0.1:7860
docker compose run --rm cli checar     # a CLI na mesma imagem
docker compose run --rm cli falar douglas "Olá, mundo."
```

A porta é publicada só em `127.0.0.1`. `vozes/` e `saida/` ficam no host; os
1,8 GB de pesos vão para um volume nomeado e sobrevivem a rebuild. A imagem é
CPU-only, sem CUDA e sem FFmpeg, e não embute o modelo. Detalhes no
[manual, seção 6](docs/MANUAL.md).

## Estrutura

```
compat.py         correções de compatibilidade e diagnóstico do ambiente
vozclone.py       núcleo: cadastro de vozes e síntese
falar.py          CLI
web.py            interface Gradio, com paridade à CLI
requirements.txt  dependências, com as fixações que não são opcionais
uv.toml           configuração de índice que essas fixações pressupõem
Dockerfile        imagem CPU-only, em dois estágios
docker-compose.yml serviços web e cli, volumes e porta em localhost
scripts/install.sh, uninstall.sh      instalação e remoção em Linux e macOS
scripts/install.ps1, uninstall.ps1    o mesmo no Windows
vozes/            referências cadastradas (.wav mono 22.05 kHz)
saida/            áudios gerados
AGENTS.md         contrato para agentes de IA; ver também scripts/sync-ai-surfaces.py
```

Os quatro primeiros arquivos, mais `requirements.txt`, `uv.toml` e `LICENSE`, são
exatamente o que o instalador baixa — o resto da árvore não participa de uma
síntese.

## Desempenho medido neste laptop

Medido em Intel i7-8565U (4 cores / 8 threads, sem GPU), governor `powersave`,
Linux. É a única máquina onde a síntese foi cronometrada.

| Tarefa | Tempo |
|---|---|
| Carga do modelo (uma vez por processo) | ~24 s |
| Frase curta (~5 s de áudio) | ~21 s |
| Frase curta, modo rápido (`-r`) | ~17 s |
| Parágrafo (~14 s de áudio) | ~56 s |

Ou seja: **cerca de 3 a 4 segundos de CPU por segundo de áudio**. Não é tempo
real, e sem GPU não há como chegar lá. O sistema serve para gerar áudio em lote
(narração, testes, roteiros), não para conversação ao vivo.

### Ajustes de performance já aplicados

**Threads = cores físicos, não threads lógicas.** Contraintuitivo, mas medido:
com 8 threads a mesma frase levou 54 s contra 21 s com 4 — o hyperthreading
degrada este modelo em 2,5x. O `vozclone.py` detecta os cores físicos nas três
plataformas e fixa o valor.

**Modo rápido (`-r` na CLI, checkbox na web).** Aplica quantização dinâmica int8
nas camadas Linear do GPT autoregressivo, que é o gargalo: 21 s → 17 s. Há
alguma perda de fidelidade, então está desligado por padrão — compare ouvindo
os dois antes de adotar. Onde o backend int8 não existe, avisa e segue em
float32 em vez de abortar.

**O que ainda pode ser ganho:** a CPU está em governor `powersave`. Passar para
`performance` costuma dar um ganho relevante (requer sudo):

```bash
sudo cpupower frequency-set -g performance
```

## Correções de compatibilidade

O `coqui-tts` não acompanhou as versões atuais das suas próprias dependências.
Quatro incompatibilidades foram encontradas; todas estão resolvidas, e
`falar.py checar` confirma cada uma no ambiente real.

**1. `transformers` 5.x removeu `isin_mps_friendly`**, usado pelo backbone
Tortoise do XTTS — o import de `TTS` quebra sem ele. *Resolvido em código:* o
`compat.py` repõe o símbolo sobre `torch.isin`, que é o que a implementação
original fazia fora do Apple MPS. Não há mais pin de versão: a síntese completa
foi validada em `transformers` 4.57.6 **e** 5.15.1
([ADR-0009](docs/adr/0009-transformers-5-por-reposicao-de-simbolo.md)).

**2. O wheel do `torchcodec` no PyPI é compilado contra CUDA** e não carrega
sobre um PyTorch CPU-only. Como o `torchaudio` 2.9+ delega o IO de áudio a ele, e
o XTTS chama `torchaudio.load` para ler a voz de referência, isso quebrava a
clonagem. *Resolvido na instalação:* no Linux o `requirements.txt` pede o wheel
`+cpu`, publicado no índice do PyTorch, que carrega sem CUDA nenhum. A hipótese
inicial — que a saída seria instalar CUDA — estava errada
([ADR-0003](docs/adr/0003-io-audio-via-soundfile.md)).

**3. O `torchaudio` 2.11 removeu `torchaudio.info`**, que o `coqui-tts` ainda
chama. *Resolvido em código:* o `compat.py` redireciona `load`, `save` e `info`
para o `soundfile`. Esse patch continua ativo mesmo com o wheel correto, por
decisão de projeto: mantém o XTTS fora da pilha FFmpeg do `torchcodec` e faz o
sistema degradar em vez de quebrar num ambiente montado com o wheel errado.

**4. O `TTS/__init__.py` exige o `torchcodec` instalado** com PyTorch 2.9+, mesmo
sem usá-lo — daí o extra `coqui-tts[codec]` no manifesto. Neutralizar a guarda em
código foi tentado e **quebra** o `transformers` 5, que passa a procurar a versão
de um pacote inexistente; o registro dessa tentativa está no ADR-0009.

Duas fixações seguem não sendo opcionais, agora dentro do `requirements.txt` em
vez de na prosa: o **PyTorch CPU-only no Linux** (evita ~2,5 GB de dependências
CUDA inúteis sem GPU) e o **wheel `+cpu` do `torchcodec`**.

## Licença e uso responsável

O XTTS-v2 usa a **Coqui Public Model License (CPML)**, que **proíbe uso
comercial**. Este projeto foi configurado para uso pessoal e experimentação; a
variável `COQUI_TOS_AGREED=1` em `vozclone.py` registra o aceite dessa licença.
Para uso comercial seria necessário trocar o motor pelo Chatterbox (MIT).

Clonagem de voz exige **consentimento explícito** de quem tem a voz clonada.
Não use o sistema para imitar terceiros sem autorização, nem para gerar
conteúdo que se passe por outra pessoa.

Ao compartilhar áudios gerados ou referências de voz com terceiros, tenha
cuidado: áudio de voz é dado biométrico. Mantenha o conteúdo de `vozes/` fora de
repositórios e canais compartilhados.
