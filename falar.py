#!/usr/bin/env python3
"""CLI do clonador de voz. Use --help para ver os comandos."""

import argparse
import sys

# No Windows, com a saída redirecionada para arquivo ou pipe, o encoding
# padrão é o do locale (cp1252) e os acentos quebram com UnicodeEncodeError.
for _fluxo in (sys.stdout, sys.stderr):
    try:
        _fluxo.reconfigure(encoding="utf-8")
    except (AttributeError, OSError, ValueError):
        pass

from vozclone import IDIOMAS, Resultado, cadastrar_voz, listar_vozes, sintetizar


def cmd_vozes(_args) -> int:
    vozes = listar_vozes()
    if not vozes:
        print("Nenhuma voz cadastrada. Use: falar.py cadastrar <nome> <audio.wav>")
        return 1
    print("Vozes cadastradas:")
    for v in vozes:
        print(f"  - {v}")
    return 0


def cmd_cadastrar(args) -> int:
    destino = cadastrar_voz(args.nome, args.audio)
    print(f"Voz '{args.nome}' cadastrada em {destino}")
    return 0


def cmd_falar(args) -> int:
    texto = args.texto
    if args.arquivo:
        texto = open(args.arquivo, encoding="utf-8").read()

    print(f"Carregando XTTS-v2 (primeira execução leva ~30s)...", file=sys.stderr)
    r: Resultado = sintetizar(
        texto=texto,
        voz=args.voz,
        idioma=args.idioma,
        saida=args.saida,
        velocidade=args.velocidade,
        rapido=args.rapido,
    )
    print(f"\nÁudio: {r.caminho}")
    print(f"Duração: {r.duracao_audio:.1f}s | Geração: {r.tempo_geracao:.1f}s "
          f"| Fator: {r.fator_tempo_real:.2f}x tempo real")
    return 0


def cmd_checar(_args) -> int:
    """Confere as correções de compatibilidade e o ambiente (ver compat.py)."""
    import compat

    falhas = 0
    for ok, item, detalhe in compat.verificar():
        print(f"  {'ok  ' if ok else 'FALHA'} {item}: {detalhe}")
        falhas += not ok
    if falhas:
        print(f"\n{falhas} verificação(ões) falharam — ver docs/MANUAL.md.", file=sys.stderr)
        return 1
    print("\nAmbiente consistente.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        prog="falar.py", description="Clonagem de voz local com XTTS-v2 (pt-BR / en-US)"
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("vozes", help="lista as vozes cadastradas").set_defaults(func=cmd_vozes)

    sub.add_parser(
        "checar", help="verifica as correções de compatibilidade e o ambiente"
    ).set_defaults(func=cmd_checar)

    c = sub.add_parser("cadastrar", help="cadastra uma voz a partir de um áudio")
    c.add_argument("nome")
    c.add_argument("audio", help="wav/mp3/flac com 6-30s de fala limpa")
    c.set_defaults(func=cmd_cadastrar)

    f = sub.add_parser("falar", help="gera áudio a partir de texto")
    f.add_argument("voz")
    f.add_argument("texto", nargs="?", default="")
    f.add_argument("-f", "--arquivo", help="lê o texto de um arquivo .txt")
    f.add_argument("-i", "--idioma", default="pt-br", choices=list(IDIOMAS))
    f.add_argument("-o", "--saida", help="caminho do .wav de saída")
    f.add_argument("-v", "--velocidade", type=float, default=1.0)
    f.add_argument("-r", "--rapido", action="store_true",
                   help="quantização int8: ~20%% mais rápido, leve perda de fidelidade")
    f.set_defaults(func=cmd_falar)

    args = p.parse_args()
    if args.cmd == "falar" and not args.texto and not args.arquivo:
        p.error("informe um texto ou use --arquivo")

    try:
        return args.func(args)
    except (FileNotFoundError, ValueError) as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
