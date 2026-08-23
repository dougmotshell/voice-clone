<!-- managed-by:voice-clone/sync-ai-surfaces — do not edit by hand -->
---
name: smoke-test
description: Verifica o ambiente do clonador de voz e gera um áudio de verdade, que é a única prova de que a clonagem funciona. Use após instalar, após atualizar dependência, antes de commitar mudança em compat.py, vozclone.py, requirements.txt ou Dockerfile.
---
<!-- fonte: skills/smoke-test/SKILL.md -->

# Teste de fumaça do clonador de voz

Import bem-sucedido **não** é prova neste projeto: já houve caso de `import TTS`
passar com a clonagem quebrada, porque o XTTS só toca no IO de áudio ao ler a
voz de referência. A prova é um .wav gerado.

Mesmo assunto em outros lugares: `compat.verificar()` (as checagens), `AGENTS.md`
(as armadilhas), `docs/MANUAL.md` (solução de problemas).

## Passos

1. **Ambiente.** `.venv/bin/python falar.py checar`. Toda linha precisa vir `ok`.
   Uma linha `FALHA` para aqui — leve para o agente `compat-doctor`.

2. **Voz de referência.** `.venv/bin/python falar.py vozes`. Sem nenhuma voz,
   cadastre uma com 6–30 s de fala limpa antes de seguir.

3. **Síntese em pt-BR.**
   ```bash
   .venv/bin/python falar.py falar <voz> "Teste de fumaça do clonador de voz."
   ```
   Espere ~24 s de carga mais ~3 a 4 s de CPU por segundo de áudio. Não é lento
   por defeito: é o custo de XTTS em CPU.

4. **Síntese em en-US**, que exercita outro caminho de tokenização:
   ```bash
   .venv/bin/python falar.py falar <voz> "Smoke test." -i en-us
   ```

5. **Confira o áudio, não só o código de saída.** Duração coerente com o texto e
   RMS diferente de zero:
   ```bash
   .venv/bin/python -c "import soundfile as sf, numpy as np; \
     d, sr = sf.read('<arquivo>'); \
     print(len(d)/sr, 'segundos, rms', float(np.sqrt((d**2).mean())))"
   ```
   Um .wav de silêncio passa por todos os passos anteriores sem erro.

6. **Se mexeu em `web.py`**, repita pela interface: as duas superfícies têm de
   ter paridade, e a web tem caminhos que a CLI não tem (upload de .txt,
   pré-carga do modelo).

7. **Se mexeu no Dockerfile ou no compose**, repita dentro do contêiner:
   ```bash
   docker compose run --rm cli checar
   docker compose run --rm cli falar <voz> "Teste no contêiner."
   ```

## Relate

Comando, saída de verdade (colada, não parafraseada), duração e RMS do áudio, e
o tempo de geração. Se algum passo foi pulado, diga qual e por quê.
