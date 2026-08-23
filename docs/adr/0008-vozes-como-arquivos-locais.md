# ADR-0008 — Vozes como arquivos WAV no filesystem

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

O sistema precisa persistir as vozes cadastradas entre execuções. Como a
clonagem do XTTS-v2 é zero-shot, o que se guarda não é um modelo treinado: é o
**próprio áudio de referência**, reprocessado a cada síntese.

Isso torna a decisão de armazenamento também uma decisão de segurança da
informação: **gravação de voz é dado biométrico**, categoria de dado pessoal
sensível sob a LGPD.

## Decisão

Armazenar cada voz como um arquivo `vozes/<nome>.wav`, normalizado no cadastro
para mono, 22.050 Hz, PCM 16 bits, com pico em 0,95.

Sem banco de dados, sem índice, sem metadados. O nome do arquivo é o
identificador da voz, e `listar_vozes()` é um `glob` no diretório.

Controles aplicados:

- `vozes/` e `saida/` estão no `.gitignore` — nenhuma amostra de voz vai para
  controle de versão.
- Tudo permanece no filesystem local; nenhuma escrita fora do diretório do
  projeto e do cache de pesos.
- Normalização no cadastro garante que os arquivos guardados sejam sempre do
  mesmo formato, sem cópias intermediárias espalhadas.

## Consequências

**Positivas**
- Inspeção e remoção triviais: `ls vozes/`, `rm vozes/nome.wav`. Apagar o dado
  biométrico é apagar um arquivo — relevante para atender pedidos de exclusão.
- Sem dependência de banco e sem estado oculto.
- Backup e cópia entre máquinas são operações de arquivo.

**Negativas**
- **Sem cifragem em repouso.** Os WAVs ficam em claro no disco do usuário. Aceito
  porque o escopo é uso pessoal numa máquina de trabalho; num cenário
  multiusuário ou de servidor compartilhado, esta decisão precisaria ser revista.
- Sem metadados: não há registro de quem consentiu com a clonagem, quando a voz
  foi cadastrada ou por quanto tempo pode ser usada. O consentimento é um
  controle de processo, não de sistema.
- Sem controle de acesso além das permissões do sistema de arquivos.
- Nomes de voz não são validados contra travessia de caminho — um nome contendo
  `../` escreveria fora do diretório previsto. Não explorável por rede (a
  interface é local), mas é uma aspereza conhecida.

## Notas

Se o sistema evoluir para múltiplos usuários ou execução em servidor, três itens
passam a ser obrigatórios: cifragem em repouso, registro de consentimento com
prazo de validade, e sanitização dos nomes de voz.
