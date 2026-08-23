<!-- managed-by:voice-clone/sync-ai-surfaces — do not edit by hand -->
---
applyTo: "docs/adr/**"
---
<!-- fonte: .claude/rules/adr.md -->

# Regras para os ADRs

Procedimento completo na skill `new-adr`; template em `templates/adr.md`; índice
em `docs/adr/README.md`.

- **Não reescreva um ADR aceito.** O registro vale por mostrar o que se pensava
  na época. Raciocínio errado ganha `## Revisão — <data>`; decisão trocada ganha
  ADR novo, e o antigo passa a `Substituído por ADR-NNNN`.
- **Cabeçalho sempre com `**Status:**` e `**Data:**`** no formato dos vizinhos.
- **Contexto com evidência**: erro real, número medido, saída de comando.
- **Consequências negativas são obrigatórias.**
- Toda mudança de status entra também na tabela de `docs/adr/README.md`.
