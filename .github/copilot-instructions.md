# Instruções do Copilot — Clonador de Voz Local

@AGENTS.md

`AGENTS.md` é o contrato canônico deste projeto: convenções, armadilhas e regras
de dados sensíveis ficam lá. Este arquivo carrega só o que é específico do
Copilot.

## Regras por caminho

`.github/instructions/*.instructions.md` traz regras com `applyTo:`, carregadas
quando um arquivo correspondente é aberto. São **geradas** a partir de
`.claude/rules/` — edite a fonte, não a saída.

## Prompts

`.github/prompts/*.prompt.md` são **gerados** a partir de `skills/`. Cada um
carrega banner na primeira linha.

## Arquivos gerados

Não edite nada em `.github/prompts/`, `.github/instructions/`, `.claude/skills/`,
`.claude/commands/`, `.agents/skills/` ou `.codex/`. Edite a fonte e rode:

```bash
python3 scripts/sync-ai-surfaces.py
```
