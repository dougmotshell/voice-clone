# CLAUDE.md

@AGENTS.md

`AGENTS.md` é o contrato canônico deste projeto: convenções, armadilhas e regras
de dados sensíveis ficam lá, não aqui. Este arquivo carrega só o que é
específico do Claude Code.

## Subagentes

| Agente | Quando usar |
|---|---|
| `compat-doctor` | Erro de import, de wheel ou de versão de dependência. Ele lê `compat.py`, roda `falar.py checar` e cruza com os ADRs antes de propor mudança. |

## Comandos de barra

Gerados a partir de `skills/` por `scripts/sync-ai-surfaces.py`:

| Comando | O que faz |
|---|---|
| `/smoke-test` | Verifica o ambiente e gera um áudio de verdade — a única prova que vale. |
| `/new-adr` | Cria um ADR novo no formato do projeto e atualiza o índice. |

## Arquivos gerados

Não edite nada em `.claude/skills/`, `.claude/commands/`, `.agents/skills/`,
`.codex/` ou `.github/{prompts,instructions}/`: é saída de gerador e carrega
banner na primeira linha. Edite a fonte em `skills/`, `.claude/agents/` ou
`.claude/rules/` e rode `python3 scripts/sync-ai-surfaces.py`.

## MCP

Este projeto não declara servidores MCP próprios (`.mcp.json` não existe).
TODO: se algum for adicionado, listar aqui o que ele serve.
