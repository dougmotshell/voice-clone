# Documentação — Clonador de Voz Local

## Para usar o sistema

**[Manual de uso](MANUAL.md)** — instalação, preparo do áudio de referência,
operação pela web e pela CLI, uso como biblioteca, desempenho esperado, solução
de problemas e uso responsável.

## Para entender o sistema

**[Software Design Document](SDD.md)** — requisitos, arquitetura, desenho
detalhado dos módulos, modelo de dados, análise de desempenho, segurança da
informação, dependências e caminhos de evolução.

**[Modelo C4](c4/README.md)** — diagramas de contexto, contêiner e componente,
mais os fluxos de cadastro e síntese.

**[Architecture Decision Records](adr/)** — oito decisões registradas, com o
contexto em que foram tomadas e as consequências aceitas.

## Por onde começar

| Objetivo | Leia |
|---|---|
| Gerar áudio hoje | [Manual](MANUAL.md), seções 2 e 3 |
| Entender a arquitetura | [C4](c4/README.md), depois [SDD](SDD.md) §3 |
| Saber por que o XTTS-v2 | [ADR-0001](adr/0001-motor-tts-xtts-v2.md) |
| Investigar lentidão | [SDD](SDD.md) §6 e [ADR-0005](adr/0005-threads-cores-fisicos.md) |
| Avaliar riscos e conformidade | [SDD](SDD.md) §7 e [ADR-0008](adr/0008-vozes-como-arquivos-locais.md) |
| Diagnosticar erro de import | [ADR-0003](adr/0003-io-audio-via-soundfile.md) e [ADR-0004](adr/0004-fixar-transformers-4x.md) |
