# ADR-0006 — Quantização int8 como opção, não como padrão

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

Com ~3–4 segundos de CPU por segundo de áudio, o desempenho é o ponto fraco
conhecido da solução ([ADR-0001](0001-motor-tts-xtts-v2.md)). O gargalo é o GPT
autoregressivo do XTTS, que gera os tokens de áudio sequencialmente.

A quantização dinâmica int8 das camadas `Linear` desse GPT foi medida:

| Configuração | Tempo (frase de ~5 s) | Fator |
|---|---|---|
| Padrão (float32) | 21,4 s | 4,01x |
| int8 dinâmico no GPT | **17,1 s** | 3,00x |

Ganho de aproximadamente 20%, sem custo de memória adicional relevante.

## Decisão

Implementar a quantização como **opção explícita, desligada por padrão**,
exposta como `-r/--rapido` na CLI e como checkbox na interface web.

A razão de não ligar por padrão é honesta: **a perda de fidelidade não foi
avaliada auditivamente**. Quantização dinâmica de camadas `Linear` costuma
preservar bem a qualidade, mas num sistema cujo propósito é fidelidade de timbre,
essa é exatamente a dimensão que não se pode degradar às cegas. A avaliação é
perceptual e cabe a quem usa.

## Consequências

**Positivas**
- 20% de ganho disponível para quem aceitar a troca.
- Padrão conservador: quem não configurar nada obtém a melhor fidelidade.
- A comparação é trivial — mesma voz, mesmo texto, com e sem a flag.

**Negativas**
- A quantização é **irreversível dentro do processo**: uma vez aplicada, o
  modelo em memória fica quantizado até o processo terminar. Na interface web,
  desmarcar o checkbox após uma geração rápida não restaura o modelo original.
  A flag `_quantizado` evita reaplicar, mas não desfaz.
- Duas configurações de qualidade a documentar e suportar.
- O PyTorch 2.13 emite um `UserWarning` de depreciação da API de quantização,
  que pode virar remoção numa versão futura.

## Notas

O comportamento irreversível está documentado, mas seria corrigível recarregando
o modelo ao trocar de modo — trabalho não realizado por custar 24 s de recarga a
cada alternância.
