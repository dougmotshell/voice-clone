#!/usr/bin/env python3
"""
Projeta as fontes autoradas de IA em todas as superfícies de CLI.

Fontes (autoradas, versionadas, editáveis à mão):

    .claude/agents/<n>.md      agentes, formato nativo do Claude
    skills/<n>/SKILL.md        skills, formato Agent Skills (portável)
    .claude/rules/<n>.md       regras por caminho, com frontmatter `paths:`

Saídas (geradas, versionadas de propósito para que um clone novo funcione sem
rodar nada, e NUNCA editadas à mão):

    .claude/skills/<n>/SKILL.md            skill no diretório que o Claude lê
    .claude/commands/<n>.md                comando de barra
    .agents/skills/<n>/SKILL.md            superfície neutra
    .github/prompts/<n>.prompt.md          prompt do Copilot
    .codex/prompts/<n>.md                  prompt do Codex
    .codex/agents/<n>.toml                 agente no formato do Codex
    .github/instructions/<n>.instructions.md   regra por caminho do Copilot

Uso:
    python3 scripts/sync-ai-surfaces.py            escreve as saídas
    python3 scripts/sync-ai-surfaces.py --check    não escreve; sai 1 se divergir
    python3 scripts/sync-ai-surfaces.py --dry-run  lista o que mudaria

O `--check` serve para CI: ele falha quando alguém editou uma saída à mão ou
esqueceu de rodar o gerador depois de mexer numa fonte.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BANNER = "<!-- managed-by:voice-clone/sync-ai-surfaces — do not edit by hand -->"

DIR_AGENTES = RAIZ / ".claude/agents"
DIR_SKILLS = RAIZ / "skills"
DIR_REGRAS = RAIZ / ".claude/rules"


# --- frontmatter -----------------------------------------------------------


def separar_frontmatter(texto: str) -> tuple[dict[str, str], str]:
    """
    Devolve (campos, corpo). Parser deliberadamente mínimo: só chaves de nível
    raiz com valor escalar, mais listas de itens `- x` capturadas como texto
    bruto. Evita depender de PyYAML, que não é dependência do projeto.
    """
    if not texto.startswith("---\n"):
        return {}, texto
    fim = texto.find("\n---\n", 4)
    if fim == -1:
        return {}, texto
    bruto, corpo = texto[4:fim], texto[fim + 5 :]

    campos: dict[str, str] = {}
    chave_atual = None
    for linha in bruto.splitlines():
        if m := re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", linha):
            chave_atual, valor = m.group(1), m.group(2).strip()
            campos[chave_atual] = valor
        elif chave_atual and linha.strip().startswith("- "):
            item = linha.strip()[2:].strip().strip('"').strip("'")
            campos[chave_atual] = f"{campos[chave_atual]},{item}".lstrip(",")
    return campos, corpo


def lista(valor: str) -> list[str]:
    return [p.strip().strip('"').strip("'") for p in valor.split(",") if p.strip()]


def citar_toml(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def bloco_toml(corpo: str) -> str:
    """
    Corpo longo como string TOML multilinha.

    Prefere a forma literal, que não interpreta escapes — um `\\` no texto do
    agente quebraria a forma básica. Só recorre à básica, com escape, quando o
    corpo contém a própria delimitação literal.
    """
    corpo = corpo.strip()
    delim_literal = "'" * 3
    if delim_literal not in corpo:
        return f"{delim_literal}\n{corpo}\n{delim_literal}"
    escapado = corpo.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    return f'"""\n{escapado}\n"""'


# --- coleta ----------------------------------------------------------------


def coletar_skills() -> list[tuple[str, dict[str, str], str]]:
    itens = []
    for skill in sorted(DIR_SKILLS.glob("*/SKILL.md")):
        campos, corpo = separar_frontmatter(skill.read_text(encoding="utf-8"))
        nome = campos.get("name") or skill.parent.name
        if not campos.get("name") or not campos.get("description"):
            raise SystemExit(
                f"{skill.relative_to(RAIZ)}: frontmatter precisa de `name:` e `description:`."
            )
        itens.append((nome, campos, corpo))
    return itens


def coletar_agentes() -> list[tuple[str, dict[str, str], str]]:
    itens = []
    for agente in sorted(DIR_AGENTES.glob("*.md")):
        campos, corpo = separar_frontmatter(agente.read_text(encoding="utf-8"))
        nome = campos.get("name") or agente.stem
        if not campos.get("description"):
            raise SystemExit(f"{agente.relative_to(RAIZ)}: frontmatter precisa de `description:`.")
        itens.append((nome, campos, corpo))
    return itens


def coletar_regras() -> list[tuple[str, dict[str, str], str]]:
    itens = []
    for regra in sorted(DIR_REGRAS.glob("*.md")):
        campos, corpo = separar_frontmatter(regra.read_text(encoding="utf-8"))
        if not campos.get("paths"):
            raise SystemExit(f"{regra.relative_to(RAIZ)}: frontmatter precisa de `paths:`.")
        itens.append((regra.stem, campos, corpo))
    return itens


# --- projeção --------------------------------------------------------------


def projetar() -> dict[Path, str]:
    """Devolve {caminho relativo: conteúdo} de tudo que deve existir gerado."""
    saidas: dict[Path, str] = {}

    for nome, campos, corpo in coletar_skills():
        desc = campos["description"]
        fonte = f"skills/{nome}/SKILL.md"

        skill_md = (
            f"{BANNER}\n"
            f"---\nname: {nome}\ndescription: {desc}\n---\n"
            f"<!-- fonte: {fonte} -->\n"
            f"{corpo}"
        )
        saidas[Path(f".claude/skills/{nome}/SKILL.md")] = skill_md
        saidas[Path(f".agents/skills/{nome}/SKILL.md")] = skill_md

        saidas[Path(f".claude/commands/{nome}.md")] = (
            f"{BANNER}\n"
            f"---\ndescription: {desc}\n---\n"
            f"<!-- fonte: {fonte} -->\n"
            f"{corpo}"
        )
        saidas[Path(f".github/prompts/{nome}.prompt.md")] = (
            f"{BANNER}\n"
            f"---\nname: {nome}\ndescription: {desc}\nagent: agent\n---\n"
            f"<!-- fonte: {fonte} -->\n"
            f"{corpo}"
        )
        saidas[Path(f".codex/prompts/{nome}.md")] = (
            f"{BANNER}\n<!-- fonte: {fonte} -->\n{corpo}"
        )

    for nome, campos, corpo in coletar_agentes():
        fonte = f".claude/agents/{nome}.md"
        ferramentas = lista(campos.get("tools", ""))
        linhas = [
            f"# managed-by:voice-clone/sync-ai-surfaces — do not edit by hand",
            f"# fonte: {fonte}",
            "",
            f"name = {citar_toml(nome)}",
            f"description = {citar_toml(campos['description'])}",
        ]
        if ferramentas:
            linhas.append("tools = [" + ", ".join(citar_toml(f) for f in ferramentas) + "]")
        linhas += ["", "instructions = " + bloco_toml(corpo), ""]
        saidas[Path(f".codex/agents/{nome}.toml")] = "\n".join(linhas)

    for nome, campos, corpo in coletar_regras():
        caminhos = lista(campos["paths"])
        aplicar = ",".join(caminhos)
        saidas[Path(f".github/instructions/{nome}.instructions.md")] = (
            f"{BANNER}\n"
            f"---\napplyTo: {citar_toml(aplicar)}\n---\n"
            f"<!-- fonte: .claude/rules/{nome}.md -->\n"
            f"{corpo}"
        )

    return saidas


# --- execução --------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(description="Projeta as fontes de IA nas superfícies de CLI.")
    ap.add_argument("--check", action="store_true", help="não escreve; sai 1 se houver divergência")
    ap.add_argument("--dry-run", action="store_true", help="não escreve; lista o que mudaria")
    args = ap.parse_args()

    saidas = projetar()
    divergentes: list[tuple[str, Path]] = []

    for rel, conteudo in sorted(saidas.items()):
        destino = RAIZ / rel
        atual = destino.read_text(encoding="utf-8") if destino.exists() else None
        if atual == conteudo:
            continue
        divergentes.append(("desatualizado" if atual is not None else "ausente", rel))
        if not (args.check or args.dry_run):
            destino.parent.mkdir(parents=True, exist_ok=True)
            destino.write_text(conteudo, encoding="utf-8")

    # Saída gerada que não corresponde a nenhuma fonte: sobra de renomeação.
    orfas: list[Path] = []
    for raiz_gerada in (".claude/skills", ".claude/commands", ".agents/skills",
                        ".github/prompts", ".github/instructions", ".codex"):
        base = RAIZ / raiz_gerada
        if not base.exists():
            continue
        for arquivo in base.rglob("*"):
            if arquivo.is_file() and arquivo.relative_to(RAIZ) not in saidas:
                orfas.append(arquivo.relative_to(RAIZ))

    for estado, rel in divergentes:
        print(f"  {estado:14} {rel}")
    for rel in sorted(orfas):
        print(f"  {'órfã':14} {rel}  (sem fonte correspondente — remova à mão)")

    if args.check:
        if divergentes or orfas:
            print(f"\n--check falhou: {len(divergentes)} divergente(s), {len(orfas)} órfã(s).")
            print("Rode: python3 scripts/sync-ai-surfaces.py")
            return 1
        print(f"{len(saidas)} arquivo(s) gerado(s) em dia.")
        return 0

    if args.dry_run:
        print(f"\n{len(divergentes)} arquivo(s) seriam escritos de {len(saidas)}.")
        return 0

    print(f"\n{len(divergentes)} escrito(s), {len(saidas)} no total.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
