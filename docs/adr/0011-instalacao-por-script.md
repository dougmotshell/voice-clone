# ADR-0011 — Instalação e desinstalação por script, com download direto dos arquivos de execução

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

Até aqui, usar o projeto exigia clonar o repositório e conduzir o ambiente à
mão: `uv venv`, `uv pip install -r requirements.txt`, e depois invocar sempre
`.venv/bin/python falar.py …` de dentro do diretório. Três problemas concretos:

1. **Não havia caminho de saída.** O projeto deixa rastro em dois lugares que o
   usuário não escolheu e não vê: `~/.local/share/tts`, com **1,8 GB** de pesos
   do XTTS-v2 baixados no primeiro uso, e as referências de voz em `vozes/`.
   Medido nesta máquina:

   ```
   $ du -sh ~/.local/share/tts
   1.8G	/home/douglas-silva/.local/share/tts
   ```

   Quem apagasse o clone ficaria com os 1,8 GB órfãos, sem nada que indicasse
   onde estavam.

2. **A invocação vazava a estrutura do repositório.** `.venv/bin/python falar.py`
   só funciona a partir da raiz do clone, e o `README` precisava repetir a
   variante Windows (`.venv\Scripts\python`) em cada exemplo.

3. **Clonar traz o que não executa.** A árvore tem docs, dez ADRs, diagramas C4,
   `templates/`, e as superfícies de IA geradas em `.claude/`, `.agents/`,
   `.codex/` e `.github/`. Nada disso participa de uma síntese. Os arquivos que
   participam são sete.

## Alternativas avaliadas

1. **Publicar no PyPI e instalar com `pipx install`** — rejeitada. O manifesto
   deste projeto depende de um segundo índice (`download.pytorch.org`) e da
   estratégia `unsafe-best-match` declarada em `uv.toml`
   ([ADR-0010](0010-portabilidade-tres-plataformas.md)). Um pacote no PyPI não
   impõe índice extra nem estratégia de resolução a quem o instala: o
   `pip install` do usuário resolveria `torch` pelo PyPI e traria de volta os
   ~2,5 GB de CUDA que o [ADR-0002](0002-pytorch-cpu-only.md) existe para
   evitar. Além disso, publicar num índice público um clonador de voz sob
   licença não comercial não é objetivo do projeto.

2. **Baixar o tarball do GitHub (`archive/refs/heads/main.tar.gz`) e extrair** —
   rejeitada. Resolve o download, mas reintroduz o problema 3: instala a árvore
   inteira, incluindo as superfícies de IA e a documentação. Exige `tar` no
   caminho e, principalmente, o que foi instalado deixa de ser auditável de
   relance — enquanto uma lista nomeada de arquivos é.

3. **Apenas documentar melhor o procedimento manual** — rejeitada. Não resolve o
   problema 1, que é o mais grave: continuaria não havendo desinstalação, e o
   dado biométrico e os 1,8 GB continuariam invisíveis.

4. **Script de instalação que baixa a lista explícita dos arquivos de execução,
   mais um desinstalador que ele deixa no próprio prefixo** — escolhida.

## Decisão

**Quatro scripts, dois por plataforma**, cobrindo as três que o ADR-0010
promete: `scripts/install.sh` e `scripts/uninstall.sh` para Linux e macOS,
`scripts/install.ps1` e `scripts/uninstall.ps1` para Windows.

**A lista de arquivos é o contrato do que se instala.** Não um clone, não um
tarball:

```sh
ARQUIVOS="compat.py vozclone.py falar.py web.py requirements.txt uv.toml LICENSE"
```

Cada um vem de `raw.githubusercontent.com/<repo>/<ref>/<arquivo>`. O
desinstalador é o oitavo download, e vai para dentro do prefixo: remover não
pode depender de rede nem de ter o repositório em disco.

**Entrada por `curl`, com o caminho de duas etapas documentado primeiro:**

```sh
curl -fsSL https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.sh | sh
```

Toda a lógica está dentro de funções, e `main "$@"` é a última linha do arquivo.
Um download truncado no meio não executa metade do instalador — deixa de
executar qualquer coisa.

**O prefixo é `~/.local/share/voice-clone`** (`%LOCALAPPDATA%\voice-clone` no
Windows), e `vozes/` e `saida/` ficam dentro dele. Não é uma escolha estética:
`vozclone.py` resolve os dois a partir de `Path(__file__).resolve().parent`, e
manter isso significou instalar sem tocar em uma linha do núcleo.

**Dois atalhos, em `~/.local/bin`:** `voice-clone` para `falar.py` e
`voice-clone-web` para `web.py`. Nomes de arquivo em en-US, como manda a
convenção do projeto; os subcomandos continuam os da CLI, em pt-BR. Se o
diretório não estiver no `PATH`, o instalador **informa a linha** a acrescentar
em vez de editar o `rc` do shell por conta própria.

**`uv` é obrigatório e não tem substituto.** Sem ele o instalador para e explica
como obtê-lo; `--instalar-uv` (`-InstalarUv`) busca o instalador oficial da
Astral. Não há recuo para `pip`: seria justamente perder a resolução de índice
que o ADR-0010 fixou.

**Um manifesto por instalação**, em `$PREFIXO/.install-manifest`, com repo, ref,
commit resolvido, data e onde foram criados os atalhos. É por ele que o
desinstalador sabe onde procurar.

**O instalador termina rodando `falar.py checar`** — a verificação que o
`AGENTS.md` define como primeiro passo de qualquer diagnóstico. Instalar sem
verificar não é instalar.

**Desinstalar preserva os dados, por padrão.** `vozes/` é dado biométrico
([ADR-0008](0008-vozes-como-arquivos-locais.md)) e os pesos são 1,8 GB de
download. Cada um sai por uma opção própria — `--remover-dados` e
`--remover-modelos` — e apagar as vozes pede confirmação digitada; sem terminal
interativo, exige `--sim` explícito. O padrão remove só o que o instalador pôs,
mantendo de pé os diretórios com conteúdo do usuário. Há `--simular` para ver a
lista antes.

**Reinstalar por cima é seguro.** A cópia é arquivo por arquivo; em nenhum
momento o prefixo é limpo.

## Consequências

**Positivas**
- Instalar virou um comando, e desinstalar existe — inclusive para os 1,8 GB que
  antes ficavam órfãos e sem endereço conhecido.
- O que é instalado cabe em uma linha de leitura: sete arquivos nomeados.
- `voice-clone falar …` funciona de qualquer diretório, e a diferença
  `bin/python` vs `Scripts\python.exe` desapareceu da documentação de uso.
- O download é de dezenas de KB, contra a árvore inteira.
- A instalação é verificada por `checar` no próprio ato.

**Negativas**
- **`curl | sh` executa código que o usuário não leu.** É a razão de o
  procedimento de duas etapas vir primeiro na documentação e no cabeçalho do
  script. Não há checksum publicado a conferir: a garantia é HTTPS até um host
  conhecido, e quem quiser exatidão deve passar `--ref <sha>` em vez de `main`,
  que é um ref móvel.
- **A lista de arquivos de execução está agora em cinco lugares** — os dois
  instaladores, os dois desinstaladores e o `Dockerfile`. Um módulo Python novo
  no projeto exige atualizar todos. TODO: se a lista crescer, vale gerá-la de
  uma fonte única, como já é feito com as superfícies de IA.
- **O Windows não foi executado de ponta a ponta.** Sem máquina Windows, os
  `.ps1` tiveram a sintaxe validada pelo parser oficial e a lógica exercitada em
  contêiner `mcr.microsoft.com/powershell` sobre Linux — o que cobriu o
  desinstalador inteiro, mas não `.venv\Scripts\python.exe` nem a escrita no
  `PATH` do usuário. Mesma limitação que o ADR-0010 já registra.
- **Instalar duas vezes em prefixos diferentes gera duas cópias do ambiente**
  (~1,7 GB cada). Os pesos, que são a parte grande, ficam fora do prefixo e são
  compartilhados.
- **O prefixo é também o diretório de dados.** Isso decorre de `__file__` em
  `vozclone.py`: se algum dia os dados forem para um diretório próprio, os
  quatro scripts mudam junto.

## Notas

Armadilhas encontradas ao construir, todas corrigidas, e que uma revisão futura
não deve reintroduzir:

- **`--ref` era ignorado em silêncio** quando o script rodava de dentro de um
  clone: a detecção de árvore local vinha antes. Quem pede um ref pede aquele
  código; a flag agora força o modo remoto.
- **`\|` em expressão básica não é portável.** O `sed` e o `grep` do macOS não
  entendem essa alternância. As duas ocorrências passaram a `grep -E`.
- **PowerShell, `Measure-Object` sobre diretório vazio** não emite objeto, e ler
  `.Sum` de `$null` é erro sob `Set-StrictMode` — que era exatamente o caso de
  `saida/` recém-criado.
- **PowerShell, `Get-Item` sem `-Force` não vê item oculto**, e `.venv` e
  `.install-manifest` são justamente isso.
- **`$PSBoundParameters` dentro de uma função é o da função**, não o do script;
  a detecção de `-Ref` explícito precisou ser capturada no escopo do script.

Verificação feita nesta máquina (Linux, i7-8565U): instalação completa em
prefixo descartável, `checar` com as sete linhas `ok`, e uma síntese real de
9,6 s de áudio em 25,7 s pelo atalho instalado. Depois, desinstalação com os
dados preservados, confirmando que `vozes/` e `saida/` sobreviveram e que
`~/.local/share/tts` permaneceu intacto.

Documentos que mudaram junto: `README.md`, `docs/MANUAL.md` (seção 2 reescrita e
seção 9, nova, sobre desinstalação), `docs/SDD.md` (§3.1, §7.2 e §8.3),
`docs/c4/README.md` (nível 2) e `AGENTS.md`.

O `curl | sh` só responde depois que estes scripts estiverem em `main`: o
instalador busca em `raw.githubusercontent.com`, que serve o que foi publicado,
não o que está no disco local.
