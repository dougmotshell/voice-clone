# Desempenho medido

Números do único hardware onde a síntese foi medida de fato. Servem de linha de
base para comparação, não de promessa. Análise completa em `docs/SDD.md` §6.

**Máquina de referência:** Intel i7-8565U, 4 cores / 8 threads, sem GPU,
governor `powersave`, Linux.

| Tarefa | Tempo |
|---|---|
| Carga do modelo (uma vez por processo) | ~24 s |
| Frase curta (~5 s de áudio) | ~21 s |
| Frase curta, modo rápido (`-r`) | ~17 s |
| Parágrafo (~14 s de áudio) | ~56 s |

Cerca de **3 a 4 segundos de CPU por segundo de áudio**. Sem GPU não há como
chegar a tempo real; o sistema serve para gerar áudio em lote.

## Já tentado

- **8 threads em vez de 4:** 54 s contra 21 s na mesma frase. Hyperthreading
  degrada este modelo em ~2,5x ([ADR-0005](../docs/adr/0005-threads-cores-fisicos.md)).
- **Quantização int8 no GPT autoregressivo:** 21 s → 17 s, com alguma perda de
  fidelidade ([ADR-0006](../docs/adr/0006-quantizacao-int8-opcional.md)).

## Não tentado

- Governor `performance` em vez de `powersave` — ganho esperado relevante,
  requer sudo, nunca medido.
- Cache do latente do falante entre sínteses da mesma voz.
- macOS e Windows: nenhuma medição ([ADR-0010](../docs/adr/0010-portabilidade-tres-plataformas.md)).
