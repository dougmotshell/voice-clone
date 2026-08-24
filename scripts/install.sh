#!/bin/sh
# Instalador do Clonador de Voz Local — Linux e macOS.
#
# Duas formas de rodar, e a primeira é a preferível:
#
#   1. baixe, leia, execute
#      curl -fsSLO https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.sh
#      less install.sh && sh install.sh
#
#   2. direto pelo pipe (não clona o repositório; baixa 8 arquivos)
#      curl -fsSL https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.sh | sh
#
# Argumentos pelo pipe precisam de `-s --`:
#      curl -fsSL .../install.sh | sh -s -- --instalar-uv
#
# O que ele faz: baixa apenas os arquivos de execução para o prefixo, cria o
# venv com `uv`, instala o requirements.txt (que carrega as fixações de wheel
# que não são opcionais — ver ADR-0002, ADR-0003 e ADR-0010), gera os dois
# lançadores e roda `falar.py checar`. Os 1,8 GB de pesos do XTTS-v2 NÃO são
# baixados aqui: isso acontece na primeira síntese.
#
# Nenhum áudio sai da máquina em momento nenhum. O tráfego de rede é o download
# do GitHub e dos índices de pacote, e para nisso.
#
# Toda a lógica está dentro de funções, chamadas por `main` na última linha:
# um download truncado não executa metade do instalador.

set -eu

REPO="${VOICE_CLONE_REPO:-dougmotshell/voice-clone}"
REF="${VOICE_CLONE_REF:-main}"
PREFIXO="${VOICE_CLONE_HOME:-$HOME/.local/share/voice-clone}"
BIN="${VOICE_CLONE_BIN:-$HOME/.local/bin}"
ORIGEM_LOCAL=""
INSTALAR_UV=0
VERIFICAR=1
# Pedir --ref ou --repo é pedir aquele código, e não o que está no disco ao
# lado do script. Sem isto, rodar de dentro de um clone ignoraria o --ref em
# silêncio e instalaria outra coisa.
REMOTO_PEDIDO=0

# Os arquivos que a execução exige. É esta lista — e não um clone — que define
# o que o instalador baixa; docs, ADRs e superfícies de IA ficam de fora.
ARQUIVOS="compat.py vozclone.py falar.py web.py requirements.txt uv.toml LICENSE"

# O desinstalador vai para dentro do prefixo, para que remover não exija rede.
ARQUIVO_DESINSTALADOR="scripts/uninstall.sh"

VERMELHO=''
VERDE=''
AMARELO=''
NEUTRO=''
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    VERMELHO=$(printf '\033[31m')
    VERDE=$(printf '\033[32m')
    AMARELO=$(printf '\033[33m')
    NEUTRO=$(printf '\033[0m')
fi

msg() { printf '%s\n' "$*"; }
passo() { printf '%s==>%s %s\n' "$VERDE" "$NEUTRO" "$*"; }
aviso() { printf '%saviso:%s %s\n' "$AMARELO" "$NEUTRO" "$*" >&2; }
erro() { printf '%serro:%s %s\n' "$VERMELHO" "$NEUTRO" "$*" >&2; exit 1; }

ajuda() {
    cat <<'EOF'
Instala o Clonador de Voz Local (XTTS-v2, offline, CPU) em Linux e macOS.

Uso: install.sh [opções]

  --prefixo DIR     onde instalar         (padrão: ~/.local/share/voice-clone)
  --bin DIR         onde criar os atalhos (padrão: ~/.local/bin)
  --ref REF         branch, tag ou commit a baixar (padrão: main)
  --repo OWNER/NOME repositório de origem
  --local DIR       instala a partir de uma árvore já presente, sem rede
  --instalar-uv     instala o uv se ele não estiver disponível
  --sem-verificar   não roda `falar.py checar` no fim
  --ajuda           esta mensagem

As mesmas escolhas por ambiente: VOICE_CLONE_HOME, VOICE_CLONE_BIN,
VOICE_CLONE_REPO, VOICE_CLONE_REF.

Rodando de dentro de um clone, o padrão é instalar a árvore que está ali.
Passar --ref ou --repo troca isso e busca o código no GitHub.

Instalar de novo por cima é seguro: vozes/ e saida/ nunca são tocados.
Para remover, rode o uninstall.sh que fica no prefixo.
EOF
}

ler_argumentos() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --prefixo) [ $# -ge 2 ] || erro "--prefixo exige um diretório."; PREFIXO="$2"; shift 2 ;;
            --bin) [ $# -ge 2 ] || erro "--bin exige um diretório."; BIN="$2"; shift 2 ;;
            --ref) [ $# -ge 2 ] || erro "--ref exige um valor."; REF="$2"; REMOTO_PEDIDO=1; shift 2 ;;
            --repo) [ $# -ge 2 ] || erro "--repo exige OWNER/NOME."; REPO="$2"; REMOTO_PEDIDO=1; shift 2 ;;
            --local) [ $# -ge 2 ] || erro "--local exige um diretório."; ORIGEM_LOCAL="$2"; shift 2 ;;
            --instalar-uv) INSTALAR_UV=1; shift ;;
            --sem-verificar) VERIFICAR=0; shift ;;
            --ajuda|--help|-h) ajuda; exit 0 ;;
            *) erro "Opção desconhecida: $1 (use --ajuda)" ;;
        esac
    done
}

# Rodando de dentro de um clone, usa a árvore local em vez da rede. Pelo pipe,
# $0 é "sh" ou "-" e não resolve para arquivo nenhum — daí o teste por -r.
detectar_origem() {
    [ -n "$ORIGEM_LOCAL" ] && return 0
    [ "$REMOTO_PEDIDO" -eq 1 ] && return 0
    case "${0:-}" in
        */*) ;;
        *) return 0 ;;
    esac
    [ -r "$0" ] || return 0
    raiz=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
    if [ -f "$raiz/vozclone.py" ] && [ -f "$raiz/requirements.txt" ]; then
        ORIGEM_LOCAL="$raiz"
    fi
    return 0
}

baixar() {
    url="$1"
    destino="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$destino" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only --tries=3 -O "$destino" "$url"
    else
        erro "Nem curl nem wget disponíveis — instale um dos dois."
    fi
}

# HTTPS de host conhecido é a garantia de origem que existe aqui; não há
# checksum publicado. Este teste pega o outro caso real: resposta HTML de
# portal cativo ou de proxy, que passaria pelo curl com status 200.
validar_baixado() {
    arquivo="$1"
    [ -s "$arquivo" ] || erro "Download vazio: $(basename "$arquivo")"
    if head -c 200 "$arquivo" | grep -qiE '<!doctype html|<html'; then
        erro "O download de $(basename "$arquivo") veio como HTML, não como código.
       Alguma coisa entre você e o GitHub está respondendo no lugar dele."
    fi
}

obter_arquivos() {
    origem="$1"
    if [ -n "$ORIGEM_LOCAL" ]; then
        passo "Copiando de $ORIGEM_LOCAL"
        for arquivo in $ARQUIVOS; do
            [ -f "$ORIGEM_LOCAL/$arquivo" ] || erro "Falta $arquivo em $ORIGEM_LOCAL."
            cp "$ORIGEM_LOCAL/$arquivo" "$origem/$(basename "$arquivo")"
        done
        if [ -f "$ORIGEM_LOCAL/$ARQUIVO_DESINSTALADOR" ]; then
            cp "$ORIGEM_LOCAL/$ARQUIVO_DESINSTALADOR" "$origem/uninstall.sh"
        fi
        return 0
    fi

    base="https://raw.githubusercontent.com/$REPO/$REF"
    passo "Baixando $REPO@$REF (8 arquivos, sem clonar o repositório)"
    for arquivo in $ARQUIVOS "$ARQUIVO_DESINSTALADOR"; do
        destino="$origem/$(basename "$arquivo")"
        baixar "$base/$arquivo" "$destino" ||
            erro "Não consegui baixar $arquivo de $base.
       Confira a rede, e se o ref '$REF' existe em $REPO."
        validar_baixado "$destino"
    done
}

garantir_uv() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi
    if [ "$INSTALAR_UV" -eq 0 ]; then
        erro "O uv não está instalado, e é ele que resolve os wheels certos.

       Instale pelo gerenciador do seu sistema, ou pelo instalador oficial
       documentado em https://docs.astral.sh/uv/getting-started/installation/

       Ou rode este script de novo com --instalar-uv, que busca esse mesmo
       instalador oficial da Astral e o executa.

       Não troque por pip: o uv.toml deste projeto carrega a estratégia de
       índice que o requirements.txt pressupõe (ADR-0010)."
    fi
    passo "Instalando o uv pelo instalador oficial da Astral"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 https://astral.sh/uv/install.sh | sh
    else
        wget -qO- --https-only https://astral.sh/uv/install.sh | sh
    fi
    # O instalador do uv põe o binário aqui e não recarrega o PATH da sessão.
    for candidato in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
        if [ -x "$candidato/uv" ]; then
            PATH="$candidato:$PATH"
            export PATH
        fi
    done
    command -v uv >/dev/null 2>&1 ||
        erro "Instalei o uv mas ele não apareceu no PATH. Abra um terminal novo e rode este script de novo."
}

instalar_arquivos() {
    origem="$1"
    passo "Instalando em $PREFIXO"
    mkdir -p "$PREFIXO" "$PREFIXO/vozes" "$PREFIXO/saida"
    # Copia arquivo por arquivo, nunca limpando o prefixo: reinstalar por cima
    # não pode encostar em vozes/ nem em saida/ — é dado biométrico do usuário.
    for arquivo in $ARQUIVOS; do
        cp "$origem/$(basename "$arquivo")" "$PREFIXO/"
    done
    if [ -f "$origem/uninstall.sh" ]; then
        cp "$origem/uninstall.sh" "$PREFIXO/uninstall.sh"
        chmod +x "$PREFIXO/uninstall.sh"
    fi
}

preparar_ambiente() {
    passo "Criando o ambiente Python 3.12 (o uv baixa o interpretador se faltar)"
    uv venv --python 3.12 "$PREFIXO/.venv" >/dev/null

    python_venv="$PREFIXO/.venv/bin/python"
    [ -x "$python_venv" ] || erro "O venv não foi criado em $PREFIXO/.venv."

    # Só agora existe um Python garantido para compilar o que foi baixado.
    # Um arquivo truncado no meio quebraria bem mais tarde, na primeira síntese.
    for arquivo in compat.py vozclone.py falar.py web.py; do
        "$python_venv" -m py_compile "$PREFIXO/$arquivo" 2>/dev/null ||
            erro "$arquivo não compila — o download veio corrompido. Rode o instalador de novo."
    done
    rm -rf "$PREFIXO/__pycache__"

    passo "Instalando as dependências (~1,7 GB; demora alguns minutos)"
    # cd no prefixo porque é lá que está o uv.toml, e é dele que vem a
    # estratégia de índice que o requirements.txt pressupõe (ADR-0010).
    ( cd "$PREFIXO" && VIRTUAL_ENV="$PREFIXO/.venv" uv pip install -r requirements.txt ) ||
        erro "A instalação das dependências falhou. Resolvido o motivo, rode o instalador de novo — ele retoma daqui."
}

criar_lancadores() {
    passo "Criando os atalhos em $BIN"
    mkdir -p "$BIN"
    for par in "voice-clone:falar.py" "voice-clone-web:web.py"; do
        nome=${par%%:*}
        alvo=${par#*:}
        cat > "$BIN/$nome" <<EOF
#!/bin/sh
# Gerado por install.sh do voice-clone. Remova com $PREFIXO/uninstall.sh.
exec "$PREFIXO/.venv/bin/python" "$PREFIXO/$alvo" "\$@"
EOF
        chmod +x "$BIN/$nome"
    done
}

escrever_manifesto() {
    commit="(não resolvido)"
    if [ -z "$ORIGEM_LOCAL" ] && command -v curl >/dev/null 2>&1; then
        resolvido=$(curl -fsSL "https://api.github.com/repos/$REPO/commits/$REF" 2>/dev/null |
            sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -1) || resolvido=""
        [ -n "$resolvido" ] && commit="$resolvido"
    fi
    cat > "$PREFIXO/.install-manifest" <<EOF
# Gerado por install.sh — o uninstall.sh lê este arquivo. Não edite.
repo=$REPO
ref=$REF
commit=$commit
origem=${ORIGEM_LOCAL:-$REPO@$REF}
instalado_em=$(date -u +%Y-%m-%dT%H:%M:%SZ)
prefixo=$PREFIXO
bin=$BIN
lancadores=voice-clone voice-clone-web
EOF
}

verificar_path() {
    case ":$PATH:" in
        *":$BIN:"*) return 0 ;;
    esac
    msg ""
    aviso "$BIN não está no seu PATH — os atalhos não vão ser encontrados."
    msg "       Adicione a linha abaixo ao seu ~/.bashrc ou ~/.zshrc:"
    msg ""
    msg "         export PATH=\"$BIN:\$PATH\""
    msg ""
    msg "       Até lá, chame pelo caminho completo: $BIN/voice-clone"
}

verificar_ambiente() {
    [ "$VERIFICAR" -eq 1 ] || return 0
    passo "Verificando o ambiente (equivale a falar.py checar)"
    if ! ( cd "$PREFIXO" && "$PREFIXO/.venv/bin/python" falar.py checar ); then
        aviso "A verificação apontou falhas. A saída acima diz o que fazer, e a
       seção 8 do manual detalha cada caso:
       https://github.com/$REPO/blob/$REF/docs/MANUAL.md"
        return 1
    fi
}

resumo() {
    msg ""
    msg "Instalado em $PREFIXO"
    msg ""
    msg "  voice-clone cadastrar minhavoz ~/audio.wav   cadastra uma voz (6-30s de fala limpa)"
    msg "  voice-clone falar minhavoz \"Olá, mundo.\"      gera áudio"
    msg "  voice-clone vozes                            lista as vozes cadastradas"
    msg "  voice-clone checar                           confere o ambiente"
    msg "  voice-clone-web                              interface web em http://127.0.0.1:7860"
    msg ""
    msg "  Vozes cadastradas: $PREFIXO/vozes"
    msg "  Áudios gerados:    $PREFIXO/saida"
    msg "  Desinstalar:       $PREFIXO/uninstall.sh"
    msg ""
    msg "A primeira síntese baixa 1,8 GB de pesos do XTTS-v2, uma única vez."
    msg "Depois disso nada mais sai da máquina."
    msg ""
    msg "Clonar a voz de outra pessoa exige o consentimento explícito dela, e o"
    msg "modelo é licenciado apenas para uso não comercial (CPML)."
}

main() {
    ler_argumentos "$@"
    detectar_origem

    case "$(uname -s)" in
        Linux|Darwin) ;;
        *) erro "Este script cobre Linux e macOS. No Windows use scripts/install.ps1." ;;
    esac

    case "$PREFIXO" in
        ""|"/") erro "Prefixo inválido: '$PREFIXO'" ;;
    esac

    garantir_uv

    origem_tmp=$(mktemp -d "${TMPDIR:-/tmp}/voice-clone-install.XXXXXX")
    trap 'rm -rf "$origem_tmp"' EXIT INT TERM
    obter_arquivos "$origem_tmp"
    instalar_arquivos "$origem_tmp"
    rm -rf "$origem_tmp"
    trap - EXIT INT TERM

    preparar_ambiente
    criar_lancadores
    escrever_manifesto

    estado=0
    verificar_ambiente || estado=1
    resumo
    verificar_path
    return $estado
}

main "$@"
