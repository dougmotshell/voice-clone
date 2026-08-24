#!/bin/sh
# Desinstalador do Clonador de Voz Local — Linux e macOS.
#
#   ~/.local/share/voice-clone/uninstall.sh              remove o programa
#   ~/.local/share/voice-clone/uninstall.sh --simular    mostra o que faria
#   ~/.local/share/voice-clone/uninstall.sh --tudo       remove também os dados
#
# O padrão remove o programa e preserva os dados. Isso é deliberado: `vozes/`
# guarda referências de voz, que são dado biométrico, e o cache de pesos são
# 1,8 GB que ninguém quer baixar de novo por acidente. Apagar qualquer um dos
# dois exige pedir explicitamente, e confirmar.
#
# O install.sh deixa uma cópia deste script dentro do prefixo, então desinstalar
# não depende de rede nem de ter o repositório em disco.

set -eu

PREFIXO="${VOICE_CLONE_HOME:-$HOME/.local/share/voice-clone}"
BIN=""
REMOVER_DADOS=0
REMOVER_MODELOS=0
SIMULAR=0
SIM=0
LANCADORES="voice-clone voice-clone-web"

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
Remove o Clonador de Voz Local instalado por install.sh.

Uso: uninstall.sh [opções]

  --prefixo DIR        de onde remover      (padrão: ~/.local/share/voice-clone)
  --bin DIR            onde estão os atalhos (padrão: o que o manifesto registrou)
  --remover-dados      remove também vozes/ e saida/
  --remover-modelos    remove o cache de pesos do XTTS-v2 (~1,8 GB)
  --tudo               as duas opções acima juntas
  --simular            lista o que seria removido, sem remover nada
  --sim                não pergunta nada (necessário para as opções destrutivas
                       quando a entrada não é um terminal)
  --ajuda              esta mensagem

Sem --remover-dados, suas vozes cadastradas e os áudios gerados continuam
onde estão, e a mensagem final diz onde.
EOF
}

ler_argumentos() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --prefixo) [ $# -ge 2 ] || erro "--prefixo exige um diretório."; PREFIXO="$2"; shift 2 ;;
            --bin) [ $# -ge 2 ] || erro "--bin exige um diretório."; BIN="$2"; shift 2 ;;
            --remover-dados) REMOVER_DADOS=1; shift ;;
            --remover-modelos) REMOVER_MODELOS=1; shift ;;
            --tudo) REMOVER_DADOS=1; REMOVER_MODELOS=1; shift ;;
            --simular) SIMULAR=1; shift ;;
            --sim|--yes|-y) SIM=1; shift ;;
            --ajuda|--help|-h) ajuda; exit 0 ;;
            *) erro "Opção desconhecida: $1 (use --ajuda)" ;;
        esac
    done
}

# O manifesto sabe onde os atalhos foram criados; sem ele, cai no padrão.
ler_manifesto() {
    manifesto="$PREFIXO/.install-manifest"
    [ -f "$manifesto" ] || return 0
    valor_bin=$(sed -n 's/^bin=//p' "$manifesto" | head -1)
    valor_lancadores=$(sed -n 's/^lancadores=//p' "$manifesto" | head -1)
    [ -z "$BIN" ] && [ -n "$valor_bin" ] && BIN="$valor_bin"
    [ -n "$valor_lancadores" ] && LANCADORES="$valor_lancadores"
    return 0
}

# Onde o coqui-tts guarda os pesos, na mesma ordem que o trainer.io resolve.
diretorio_modelos() {
    if [ -n "${TTS_HOME:-}" ]; then
        printf '%s\n' "$TTS_HOME/tts"
    elif [ -n "${XDG_DATA_HOME:-}" ]; then
        printf '%s\n' "$XDG_DATA_HOME/tts"
    elif [ "$(uname -s)" = "Darwin" ]; then
        printf '%s\n' "$HOME/Library/Application Support/tts"
    else
        printf '%s\n' "$HOME/.local/share/tts"
    fi
}

tamanho() {
    [ -e "$1" ] || { printf '%s\n' "-"; return 0; }
    du -sh "$1" 2>/dev/null | cut -f1 || printf '%s\n' "?"
}

remover() {
    alvo="$1"
    [ -e "$alvo" ] || return 0
    if [ "$SIMULAR" -eq 1 ]; then
        msg "  removeria  $alvo  ($(tamanho "$alvo"))"
        return 0
    fi
    rm -rf "$alvo"
    msg "  removido   $alvo"
}

# Só remove um atalho que este projeto criou. Um `voice-clone` de outra origem
# no mesmo diretório não é nosso para apagar.
remover_lancador() {
    caminho="$1"
    [ -e "$caminho" ] || return 0
    if ! grep -q "install.sh do voice-clone" "$caminho" 2>/dev/null; then
        aviso "$caminho não foi criado por este instalador — deixei como estava."
        return 0
    fi
    remover "$caminho"
}

confirmar() {
    pergunta="$1"
    [ "$SIM" -eq 1 ] && return 0
    if [ ! -t 0 ]; then
        erro "$pergunta
       A entrada não é um terminal, então não posso perguntar. Repita com --sim
       se é isso mesmo que você quer."
    fi
    printf '%s [digite sim para confirmar] ' "$pergunta"
    read -r resposta
    case "$resposta" in
        sim|SIM|Sim) return 0 ;;
        *) msg "Cancelado. Nada foi removido."; exit 1 ;;
    esac
}

main() {
    ler_argumentos "$@"
    ler_manifesto
    [ -n "$BIN" ] || BIN="$HOME/.local/bin"

    case "$PREFIXO" in
        ""|"/"|"$HOME") erro "Prefixo inválido: '$PREFIXO'" ;;
    esac

    dir_modelos=$(diretorio_modelos)
    vozes="$PREFIXO/vozes"
    saida="$PREFIXO/saida"

    if [ ! -d "$PREFIXO" ]; then
        aviso "Não há instalação em $PREFIXO."
        msg "Se você instalou em outro lugar, informe com --prefixo."
        # Os atalhos podem ter sobrado de uma remoção manual do prefixo.
        for nome in $LANCADORES; do
            [ -e "$BIN/$nome" ] && msg "Mas o atalho $BIN/$nome existe — removendo."
            remover_lancador "$BIN/$nome"
        done
        exit 0
    fi

    # O prefixo pode ter sobrevivido a uma remoção anterior só por causa dos
    # dados. Dizer "instalação encontrada" ali seria mentira.
    if [ -f "$PREFIXO/vozclone.py" ]; then
        msg "Instalação encontrada em $PREFIXO"
    else
        msg "Em $PREFIXO não há programa instalado — só os seus dados."
    fi
    # grep -E, e não um BRE com \|: o sed do macOS não entende essa alternância.
    if [ -f "$PREFIXO/.install-manifest" ]; then
        grep -E '^(ref|commit|instalado_em)=' "$PREFIXO/.install-manifest" | sed 's/^/  /'
    fi
    msg ""
    msg "Vai ser removido:"
    msg "  o ambiente Python e o código      $PREFIXO  ($(tamanho "$PREFIXO"))"
    for nome in $LANCADORES; do
        [ -e "$BIN/$nome" ] && msg "  o atalho                          $BIN/$nome"
    done
    msg ""
    # Dado biométrico e 1,8 GB de download são governados por flags diferentes,
    # então cada linha carrega a sua — uma dica de rodapé só valeria para metade.
    if [ "$REMOVER_DADOS" -eq 1 ]; then
        msg "${VERMELHO}Também os seus dados${NEUTRO}:"
        msg "  vozes cadastradas   $vozes  ($(tamanho "$vozes"))"
        msg "  áudios gerados      $saida  ($(tamanho "$saida"))"
    else
        msg "Preservado:"
        msg "  vozes cadastradas   $vozes  ($(tamanho "$vozes"))   --remover-dados apaga"
        msg "  áudios gerados      $saida  ($(tamanho "$saida"))"
    fi
    if [ -d "$dir_modelos" ]; then
        if [ "$REMOVER_MODELOS" -eq 1 ]; then
            msg "  ${VERMELHO}pesos do XTTS-v2${NEUTRO}    $dir_modelos  ($(tamanho "$dir_modelos"))"
        else
            msg "  pesos do XTTS-v2    $dir_modelos  ($(tamanho "$dir_modelos"))   --remover-modelos apaga"
        fi
    fi
    msg ""

    if [ "$SIMULAR" -eq 1 ]; then
        passo "Simulação — nada será removido"
    elif [ "$REMOVER_DADOS" -eq 1 ]; then
        confirmar "Apagar as vozes cadastradas em $vozes é irreversível. Confirma?"
    fi

    passo "Removendo"

    # Os dados saem primeiro (ou ficam), e só então o diretório que os contém.
    if [ "$REMOVER_DADOS" -eq 0 ]; then
        preservados=0
        for dir in "$vozes" "$saida"; do
            if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                preservados=1
            fi
        done
        if [ "$preservados" -eq 1 ]; then
            # Remove só o que o instalador pôs, deixando vozes/ e saida/ de pé.
            for arquivo in compat.py vozclone.py falar.py web.py requirements.txt \
                           uv.toml LICENSE .install-manifest uninstall.sh; do
                remover "$PREFIXO/$arquivo"
            done
            remover "$PREFIXO/.venv"
            remover "$PREFIXO/__pycache__"
        else
            remover "$PREFIXO"
        fi
    else
        remover "$PREFIXO"
    fi

    [ "$REMOVER_MODELOS" -eq 1 ] && remover "$dir_modelos"

    for nome in $LANCADORES; do
        remover_lancador "$BIN/$nome"
    done

    msg ""
    if [ "$SIMULAR" -eq 1 ]; then
        msg "Nada foi removido. Tire o --simular para valer."
        exit 0
    fi

    passo "Pronto."
    if [ "$REMOVER_DADOS" -eq 0 ] && [ -d "$PREFIXO" ]; then
        msg ""
        msg "Seus dados continuam onde estavam:"
        msg "  $vozes"
        msg "  $saida"
        msg ""
        msg "Áudio de voz é dado biométrico. Se não vai mais usar, apague de vez:"
        msg "  rm -rf \"$PREFIXO\""
    fi
    if [ "$REMOVER_MODELOS" -eq 0 ] && [ -d "$dir_modelos" ]; then
        msg ""
        msg "Os pesos do XTTS-v2 ($(tamanho "$dir_modelos")) ficaram em $dir_modelos —"
        msg "reinstalar reaproveita, e --remover-modelos apaga."
    fi
}

main "$@"
