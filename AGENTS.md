# AGENTS.md — Clonador de Voz Local

Contrato canônico deste projeto. Vale para qualquer CLI de IA; `CLAUDE.md` e
`.github/copilot-instructions.md` são adaptadores finos que importam este
arquivo. Edite aqui, não nos adaptadores.

Clonagem de voz com XTTS-v2, **100% offline e em CPU**. Python 3.12, sem
serviço externo e sem GPU.

## Comandos

```bash
# ambiente (Linux/macOS; no Windows, $env:VIRTUAL_ENV=".venv")
uv venv --python 3.12 .venv
VIRTUAL_ENV=.venv uv pip install -r requirements.txt

.venv/bin/python falar.py checar        # SEMPRE o primeiro passo ao diagnosticar
.venv/bin/python falar.py vozes
.venv/bin/python falar.py cadastrar <nome> <audio>
.venv/bin/python falar.py falar <voz> "texto"
.venv/bin/python web.py                 # http://127.0.0.1:7860

docker compose up --build               # web em contêiner
docker compose run --rm cli checar      # CLI em contêiner

sh scripts/install.sh                   # instala no prefixo do usuário
sh scripts/uninstall.sh --simular       # o que a remoção levaria
```

Não existe suíte de testes automatizados. A verificação de fato é
`falar.py checar` seguido de uma síntese real — trocar dependência sem gerar
áudio não prova nada. TODO: decidir se entra pytest e o que seria testável sem
baixar 1,8 GB de pesos.

## Armadilhas — leia antes de mexer

**Ordem de import é contratual.** `compat.aplicar()` precisa rodar **antes** de
qualquer `import TTS`. `vozclone.py` faz isso no topo; quem importar `TTS`
direto reintroduz falhas já resolvidas. Detalhes e o porquê em `compat.py`.

**As correções de compatibilidade não são folclore.** Três incompatibilidades
reais do `coqui-tts` estão resolvidas — símbolo reposto para o `transformers` 5,
IO de áudio por `soundfile`, wheel `+cpu` do `torchcodec`. Antes de "limpar"
qualquer uma, leia [ADR-0003](docs/adr/0003-io-audio-via-soundfile.md) e
[ADR-0009](docs/adr/0009-transformers-5-por-reposicao-de-simbolo.md): as duas
registram tentativas que já falharam.

**Nunca instale `torch` sem o índice CPU do PyTorch no Linux.** O wheel do PyPI
arrasta ~2,5 GB de CUDA numa máquina sem GPU. O `requirements.txt` prende o
`+cpu`; mantenha assim ([ADR-0002](docs/adr/0002-pytorch-cpu-only.md),
[ADR-0010](docs/adr/0010-portabilidade-tres-plataformas.md)).

**Threads = cores físicos, não lógicos.** Contraintuitivo e medido: com
hyperthreading ligado a mesma frase levou 2,5x mais tempo. Não "otimize" para
`os.cpu_count()` ([ADR-0005](docs/adr/0005-threads-cores-fisicos.md)).

**`split_sentences=True` é essencial em CPU.** Sem isso, textos longos travam.

**Licença do modelo proíbe uso comercial.** O XTTS-v2 é CPML. Não sugira este
projeto para produto pago; para isso o motor teria de mudar (Chatterbox, MIT).

**Módulo novo entra em cinco listas.** Os arquivos que a execução exige
(`compat.py`, `vozclone.py`, `falar.py`, `web.py`) estão nomeados nos quatro
scripts de `scripts/` e no `Dockerfile`. Acrescentar um `.py` ao projeto sem
atualizar todos produz uma instalação que quebra só no primeiro uso
([ADR-0011](docs/adr/0011-instalacao-por-script.md)).

**A desinstalação não apaga voz sem ser mandada.** `vozes/` é dado biométrico e
os pesos são 1,8 GB: o padrão preserva os dois, e cada um sai por uma opção
própria com confirmação. Não transforme isso em "limpa tudo por padrão".

## Dados sensíveis

Áudio de voz é **dado biométrico**. `vozes/` e `saida/` são ignorados pelo git —
não os adicione, não os cole em issues, não os envie para serviço externo.
Nenhum áudio deve sair da máquina: é o requisito central do projeto, não uma
preferência. A interface web escuta só em `127.0.0.1`, e o `docker-compose.yml`
publica a porta só em `127.0.0.1` do host; não troque por `0.0.0.0` sem
autenticação na frente.

Clonar voz de terceiro exige consentimento explícito de quem tem a voz.

## Convenções

**Idioma.** Prosa (documentação, comentários, mensagens ao usuário) em pt-BR com
acentuação completa. Identificadores, nomes de arquivo e de branch em en-US.
O código existente usa nomes de função em pt-BR (`sintetizar`, `cadastrar_voz`)
— mantenha a consistência com o que já está lá em vez de misturar.

**Decisão de arquitetura vira ADR.** Formato Nygard, um arquivo em
`docs/adr/NNNN-titulo.md`, índice em `docs/adr/README.md`, template em
`templates/adr.md`. Corrigir um ADR anterior é escrever a revisão dentro dele e,
se a decisão mudou, um ADR novo que o substitui — não reescrever a história.

**Documentação que precisa acompanhar o código:** `README.md` (visão geral),
`docs/MANUAL.md` (operação), `docs/SDD.md` (arquitetura e dependências),
`docs/c4/README.md` (diagramas). Mudança em módulo mexe no SDD e no C4.

**Paridade CLI ↔ web.** Tudo que `falar.py` faz, `web.py` também faz. Comando
novo na CLI entra como aba ou controle na web, e vice-versa.

**Nomes de voz e de saída passam por `vozclone.validar_nome()`**, que aplica as
regras do Windows em todas as plataformas: caracteres proibidos, ponto ou espaço
final, nome de dispositivo **com ou sem extensão** (`CON.wav` também é o console)
e limite de 128 caracteres. Não escreva caminho a partir de entrada do usuário
sem passar por ela, e não "simplifique" nenhuma dessas regras — cada uma cobre
uma falha concreta, registrada na revisão do
[ADR-0010](docs/adr/0010-portabilidade-tres-plataformas.md).

## Superfícies de IA

`.claude/agents/`, `skills/` e `.claude/rules/` são **autorados**. Tudo em
`.claude/skills/`, `.claude/commands/`, `.agents/skills/`, `.codex/` e
`.github/{prompts,instructions}/` é **gerado** por `scripts/sync-ai-surfaces.py`
e carrega um banner na primeira linha. Edite a fonte e rode o gerador:

```bash
python3 scripts/sync-ai-surfaces.py          # projeta
python3 scripts/sync-ai-surfaces.py --check  # falha se houver divergência
```
