# Clonador de Voz Local — imagem CPU-only, sem CUDA e sem FFmpeg.
#
# O build é em dois estágios para que o cache do uv e os artefatos de
# compilação não entrem na imagem final. O modelo (~1,8 GB) NÃO é embutido:
# ele é baixado no primeiro uso e guardado em TTS_HOME, que o
# docker-compose.yml monta como volume para sobreviver a recriações.

FROM python:3.12-slim AS build

COPY --from=ghcr.io/astral-sh/uv:0.9.9 /uv /usr/local/bin/uv

ENV UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    VIRTUAL_ENV=/opt/venv

WORKDIR /app

# uv.toml carrega a estratégia de índice que o requirements.txt pressupõe
# (ver ADR-0010); sem ele a resolução do torch falha.
COPY requirements.txt uv.toml ./

RUN uv venv "$VIRTUAL_ENV" \
 && uv pip install --no-cache -r requirements.txt


FROM python:3.12-slim AS runtime

# O soundfile traz o libsndfile no próprio wheel e o torchcodec nunca é
# importado (ver compat.py), então a imagem não precisa de FFmpeg nem de
# bibliotecas de áudio do sistema.

# UID/GID 1000 casam com o usuário padrão do host, para que vozes/ e saida/
# montados por bind continuem graváveis dos dois lados.
RUN groupadd --gid 1000 voz \
 && useradd --uid 1000 --gid 1000 --create-home voz

COPY --from=build /opt/venv /opt/venv

# COQUI_TOS_AGREED: aceite da CPML do XTTS-v2, uso não comercial (ver README).
# TTS_HOME: cache dos pesos do modelo, montado como volume pelo compose.
# VOICE_CLONE_HOST: no contêiner é preciso escutar em todas as interfaces para
# que a porta seja publicável; o compose publica só em 127.0.0.1 do host.
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    COQUI_TOS_AGREED=1 \
    TTS_HOME=/modelos \
    VOICE_CLONE_HOST=0.0.0.0 \
    VOICE_CLONE_PORT=7860

WORKDIR /app
COPY --chown=voz:voz compat.py vozclone.py falar.py web.py ./
RUN mkdir -p /app/vozes /app/saida /modelos && chown -R voz:voz /app /modelos

USER voz
EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:7860/').read(1)"

CMD ["python", "web.py"]
