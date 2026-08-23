<!-- managed-by:voice-clone/sync-ai-surfaces — do not edit by hand -->
---
name: new-adr
description: Cria um Architecture Decision Record no formato deste projeto e atualiza o índice. Use quando uma decisão de arquitetura for tomada, quando uma decisão registrada for substituída, ou quando um ADR existente precisar de revisão porque partia de premissa errada.
agent: agent
---
<!-- fonte: skills/new-adr/SKILL.md -->

# Novo ADR

Este projeto registra decisão de arquitetura em `docs/adr/`, formato
[Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions.html).
Template em `templates/adr.md`, índice em `docs/adr/README.md`, convenção geral
em `AGENTS.md`.

## Passos

1. **Confirme que é decisão de arquitetura**, e não detalhe de implementação.
   O teste: alguém que chegar em seis meses vai perguntar "por que assim?".
   Escolha de dependência, de topologia, de formato de dado: sim. Nome de
   variável, refatoração local: não.

2. **Procure o que já existe.** `grep -ril "<assunto>" docs/adr/`. Se um ADR já
   cobre o tema:
   - a decisão **mudou** → ADR novo, com `**Substitui:** [ADR-NNNN]`, e o antigo
     passa a `Substituído por ADR-NNNN` no cabeçalho e no índice;
   - a decisão **vale, mas o raciocínio tinha erro ou lacuna** → seção
     `## Revisão — <data>` dentro do próprio ADR. Não reescreva o corpo: o valor
     do registro está em mostrar o que se pensava na época.

3. **Numere em sequência**, quatro dígitos, o próximo livre em `docs/adr/`.
   Nome do arquivo em pt-BR minúsculo com hífens, como os vizinhos.

4. **Escreva a partir do template**, com estas exigências:
   - **Contexto** com evidência concreta — mensagem de erro real, número medido,
     saída de comando. Não "era lento": *quanto*, em que máquina.
   - **Alternativas avaliadas** com o motivo da rejeição de cada uma. Se uma foi
     rejeitada por premissa que depois se mostrou falsa, isso é exatamente o que
     a revisão futura vai precisar ler.
   - **Consequências** em positivas *e* negativas. Um ADR sem consequência
     negativa não foi pensado até o fim.
   - Tentativa que falhou vale registro: poupa a próxima pessoa de repeti-la.

5. **Atualize o índice** `docs/adr/README.md`: linha na tabela com número,
   título e status.

6. **Atualize o que aponta para lá.** `grep -rn "ADR-000" README.md docs/` e
   ajuste `docs/SDD.md`, `docs/README.md` e `docs/c4/README.md` se a decisão
   mexeu em módulo ou dependência.

## Relate

Caminho do ADR criado, o que mudou no índice, e a lista de documentos que
passaram a apontar para ele.
