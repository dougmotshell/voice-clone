# Clonador de Voz Local

Sistema de clonagem de voz que roda **100% offline na CPU**, sem custo e sem
enviar áudio para nenhum serviço externo. A partir de 6–30 segundos de fala,
sintetiza qualquer texto naquela voz em **pt-BR** e **en-US**.

## Documentação

| Documento | Conteúdo |
|---|---|
| **[Manual de uso](docs/MANUAL.md)** | Operação, preparo do áudio, solução de problemas |
| **[SDD](docs/SDD.md)** | Requisitos, arquitetura, desempenho, segurança |
| **[Modelo C4](docs/c4/README.md)** | Diagramas de contexto, contêiner e componente |
| **[ADRs](docs/adr/)** | As oito decisões de arquitetura e seus porquês |

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

Já está pronta em `.venv/`. Para recriar do zero:

```bash
uv venv --python 3.12 .venv
VIRTUAL_ENV=.venv uv pip install --index-url https://download.pytorch.org/whl/cpu torch torchaudio
VIRTUAL_ENV=.venv uv pip install "coqui-tts[codec]" "transformers<5" gradio
```

Duas fixações não são opcionais: o **PyTorch CPU-only** (evita ~2,5 GB de
dependências CUDA inúteis sem GPU) e o **`transformers<5`** (a série 5.x removeu
APIs que o XTTS usa e quebra o import).

## Uso pela linha de comando

```bash
# cadastrar uma voz a partir de um áudio (wav, mp3, flac)
./falar.py cadastrar douglas ~/audios/minha-voz.wav

# listar vozes
./falar.py vozes

# gerar áudio
./falar.py falar douglas "Olá, este é um teste de clonagem de voz."
./falar.py falar douglas "Hello, this is a test." -i en-us
./falar.py falar douglas -f roteiro.txt -o saida/narracao.wav -v 1.1
```

Rode com `.venv/bin/python falar.py ...` se o shebang não pegar o venv.

## Interface web

```bash
.venv/bin/python web.py
```

Abre em `http://127.0.0.1:7860`, apenas em localhost. Aba 1 grava ou envia a voz
de referência; aba 2 gera o áudio.

## Estrutura

```
vozclone.py   núcleo: cadastro de vozes e síntese
falar.py      CLI
web.py        interface Gradio
vozes/        referências cadastradas (.wav mono 22.05 kHz)
saida/        áudios gerados
```

## Desempenho medido neste laptop

Medido em Intel i7-8565U (4 cores / 8 threads, sem GPU), governor `powersave`:

| Tarefa | Tempo |
|---|---|
| Carga do modelo (uma vez por processo) | ~24 s |
| Frase curta (~5 s de áudio) | ~21 s |
| Frase curta, modo rápido (`-r`) | ~17 s |
| Parágrafo (~14 s de áudio) | ~56 s |

Ou seja: **cerca de 3 a 4 segundos de CPU por segundo de áudio**. Não é tempo
real, e sem GPU não há como chegar lá. O sistema serve para gerar áudio em lote
(narração, testes, roteiros), não para conversação ao vivo.

Como a carga do modelo é fixa em ~24 s, a interface web é bem mais confortável
que a CLI para uso repetido: o modelo fica residente entre as gerações.

### Ajustes de performance já aplicados

**Threads = cores físicos (4), não threads lógicas (8).** Contraintuitivo, mas
medido: com 8 threads a mesma frase levou 54 s contra 21 s com 4 — o
hyperthreading degrada este modelo em 2,5x. O `vozclone.py` detecta os cores
físicos e fixa o valor.

**Modo rápido (`-r` na CLI, checkbox na web).** Aplica quantização dinâmica int8
nas camadas Linear do GPT autoregressivo, que é o gargalo: 21 s → 17 s. Há
alguma perda de fidelidade, então está desligado por padrão — compare ouvindo
os dois antes de adotar.

**O que ainda pode ser ganho:** a CPU está em governor `powersave`. Passar para
`performance` costuma dar um ganho relevante (requer sudo):

```bash
sudo cpupower frequency-set -g performance
```

### Correções de compatibilidade necessárias

Três incompatibilidades foram encontradas e resolvidas na montagem:

1. **`transformers` 5.x quebra o XTTS** — removeu `isin_mps_friendly`, usado
   pelo backbone Tortoise. Fixado em `transformers<5`.
2. **`torchaudio` 2.9+ moveu o IO para o `torchcodec`**, e o wheel do torchcodec
   é compilado contra CUDA (`libcudart.so.13`, `libtorch_cuda.so`) — não carrega
   sobre um PyTorch CPU-only. Como o XTTS chama `torchaudio.load` internamente
   para ler a voz de referência, isso quebrava a clonagem. O `audio_io.py`
   redireciona `load`/`save`/`info` para `soundfile`.
3. **`coqui-tts` exige o extra `[codec]`** a partir do PyTorch 2.9, senão o
   import falha.

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
