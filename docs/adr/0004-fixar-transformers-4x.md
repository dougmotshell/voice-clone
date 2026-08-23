# ADR-0004 — Fixar `transformers` na série 4.x

**Status:** Substituído por [ADR-0009](0009-transformers-5-por-reposicao-de-simbolo.md) · **Data:** 2026-08-23

## Contexto

A instalação do `coqui-tts` trouxe `transformers 5.15.1` como dependência
transitiva. O import de `TTS` falhava imediatamente:

```
ImportError: cannot import name 'isin_mps_friendly' from 'transformers.pytorch_utils'
```

O XTTS herda o backbone autoregressivo do Tortoise, que usa
`transformers.pytorch_utils.isin_mps_friendly` — símbolo removido na série 5.x.
O `coqui-tts` ainda não foi adaptado.

## Decisão

Fixar a dependência em `transformers<5`. A resolução instalou `4.57.6`, com o
`huggingface-hub` rebaixado de `1.28.0` para `0.36.2` por compatibilidade.

## Consequências

**Positivas**
- Import e execução do XTTS funcionais.

**Negativas**
- O projeto fica preso a uma linha de `transformers` que já não é a atual, sem
  correções e melhorias da série 5.
- Compartilhar este ambiente virtual com outro projeto que exija
  `transformers>=5` causará conflito. Mitigado pelo venv dedicado.
- Uma reinstalação sem o pin reintroduz a falha silenciosamente — por isso o pin
  está documentado no README e no manual.

## Notas

A restrição sai quando o `coqui-tts` publicar suporte à série 5.x. Até lá, o pin
é obrigatório.

## Revisão — 2026-08-23

O diagnóstico acima está correto, mas a conclusão era mais forte do que os fatos
pediam. O pin foi tratado como inevitável sem que se medisse o tamanho da
incompatibilidade: é **um símbolo**, com implementação de duas linhas. Repô-lo
custa menos que ficar preso à série 4.x, e a série 5.x foi validada com síntese
completa. Ver [ADR-0009](0009-transformers-5-por-reposicao-de-simbolo.md), que
substitui esta decisão.
