# ADR-0001 — XTTS-v2 como motor de síntese

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

O sistema precisa clonar uma voz a partir de um trecho curto de áudio e
sintetizar texto arbitrário nessa voz, sob quatro restrições rígidas dadas pelo
solicitante:

1. **Custo financeiro zero** — sem APIs pagas, sem assinaturas.
2. **Execução local e offline** — nenhum áudio pode sair da máquina.
3. **Hardware disponível**: Intel i7-8565U, 4 cores, 31 GB de RAM, **sem GPU**.
4. **Idiomas**: pt-BR e en-US.

A restrição 3 é a mais limitante. A maioria dos modelos de clonagem de 2026
assume GPU, e vários simplesmente não têm caminho de inferência em CPU.

## Alternativas avaliadas

| Modelo | Licença | pt-BR | CPU | Veredito |
|---|---|---|---|---|
| **XTTS-v2** (Coqui) | CPML (não comercial) | Sim | Sim | **Escolhido** |
| Chatterbox Multilingual | MIT | Sim | Sim, lento | Vice-líder |
| Qwen3-TTS (0.6B/1.7B) | Apache-2.0 | Sim | **Não** | Exige CUDA |
| NeuTTS Air (748M, GGUF) | Apache-2.0 | **Não** | Excelente | Sem pt-BR |
| F5-TTS | MIT | Sim | Inviável | RTF ~37 em CPU |
| MisoTTS 8B | MIT modificada | Sim | Não | 8B sem GPU |
| IndexTTS-2.5 | Apache-2.0 | **Não** | — | Sem pt-BR |
| Piper / Kokoro | MIT / Apache-2.0 | Sim | Excelente | **Não clonam** zero-shot |

Dois casos merecem nota. O **NeuTTS Air** seria a escolha ideal em desempenho —
748M parâmetros em GGUF, roda até em Raspberry Pi — mas cobre apenas EN, ES, DE
e FR. O **Qwen3-TTS** é tecnicamente superior e tem licença melhor, mas não
oferece inferência em CPU.

**Piper** e **Kokoro** são rápidos em CPU e têm vozes em pt-BR, porém não fazem
clonagem zero-shot: exigiriam fine-tuning com horas de áudio da voz-alvo, o que
contraria o requisito de "aprender a voz a partir de um trecho".

## Decisão

Usar o **XTTS-v2** via o fork mantido `coqui-tts` (o repositório original da
Coqui foi abandonado e não suporta Python 3.12).

É o único candidato que satisfaz as quatro restrições simultaneamente: clona com
6 s de referência, tem pt e en nativos entre 17 idiomas, roda em CPU com 4–6 GB
de RAM e é gratuito.

## Consequências

**Positivas**
- Requisito atendido integralmente, sem custo.
- Referência curta (6 s) e sem etapa de treinamento.
- Ecossistema maduro, com documentação e comunidade.

**Negativas**
- **A CPML proíbe uso comercial.** Aceito porque o escopo declarado é uso
  pessoal e experimentação. Se isso mudar, esta ADR deve ser substituída.
- Desempenho de 3–4x o tempo real em CPU: geração em lote, não conversação.
- O fork `coqui-tts` é mantido pela comunidade, não pela Coqui — risco de
  abandono no médio prazo.
- Depende de um ecossistema (PyTorch, transformers, torchaudio) que quebrou em
  três pontos distintos durante a instalação (ver ADRs 0002, 0003 e 0004).

## Notas

O aceite da CPML é registrado em código pela variável `COQUI_TOS_AGREED=1`, em
`vozclone.py`.
