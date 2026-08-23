---
paths:
  - "*.py"
---

# Regras para os módulos Python

Contrato geral em `AGENTS.md`. Aqui só o que se aplica ao editar código.

- **`compat.aplicar()` antes de qualquer `import TTS`.** `vozclone.py` é o único
  lugar que faz isso; módulo novo deve importar `vozclone`, não `TTS`.
- **Import de `TTS` e de `torch` fica dentro da função**, não no topo do módulo.
  A carga é de segundos, e `falar.py vozes` não deve pagá-la.
- **Prosa em pt-BR acentuado**, identificadores em en-US, nomes de função no
  padrão pt-BR já usado no núcleo (`sintetizar`, `cadastrar_voz`, `validar_nome`).
- **Comentário explica *por que*, não *o quê*.** O padrão do arquivo é registrar
  a medição ou a armadilha que justifica a linha. Siga a densidade existente.
- **Erro esperado é `ValueError` ou `FileNotFoundError`**, com mensagem em pt-BR
  dizendo o que fazer. As duas interfaces já os capturam e mostram ao usuário.
- **Caminho a partir de entrada do usuário passa por `vozclone.validar_nome()`.**
- **Paridade CLI ↔ web.** Capacidade nova aparece nas duas superfícies.
- Nada de rede, telemetria ou escrita fora de `vozes/` e `saida/`.
