"""
Correções de compatibilidade entre o `coqui-tts` e as versões atuais das suas
dependências. Importe este módulo e chame `aplicar()` ANTES de importar `TTS`.

O que é resolvido em código, aqui:

1. **`transformers` >= 5 removeu `isin_mps_friendly`**, que o backbone Tortoise
   do XTTS importa — o import de `TTS` quebra sem ele. O símbolo é reposto sobre
   `torch.isin`, que é exatamente o que a implementação original fazia fora do
   Apple MPS. Com isso o projeto roda na série 4.x e na 5.x, sem fixar versão:
   a síntese foi validada de ponta a ponta em 4.57.6 e 5.15.1 (ADR-0009).

2. **`torchaudio` >= 2.9 delegou `load`/`save`/`info` ao `torchcodec`.** O XTTS
   chama `torchaudio.load` para ler a voz de referência, e o `info` deixou de
   existir no `torchaudio` 2.11. Os três passam a usar `soundfile`, que é o
   suficiente para o único formato que chega ao XTTS neste projeto (wav mono
   22.05 kHz, produzido por `vozclone.cadastrar_voz`).

O que é resolvido na instalação, não aqui (ver `requirements.txt`):

3. **O wheel do `torchcodec` no PyPI é compilado contra CUDA** (`libcudart.so`,
   `libtorch_cuda.so`) e não carrega sobre um PyTorch CPU-only. Era essa a causa
   real do problema 2 — e a correção é instalar o wheel `+cpu`, publicado no
   índice do PyTorch, que carrega sem CUDA nenhum. O `requirements.txt` prende
   `torchcodec==0.16.0+cpu`. O item 2 continua valendo por decisão de projeto:
   mantém o XTTS fora da pilha ffmpeg do torchcodec e faz o sistema sobreviver a
   um ambiente montado com o wheel errado.

4. **O `TTS/__init__.py` exige o `torchcodec` instalado** quando o PyTorch é
   >= 2.9, mesmo sem usá-lo — daí o extra `coqui-tts[codec]`. Neutralizar essa
   guarda mentindo em `is_torchcodec_available()` foi testado e **quebra** a
   máquina de import preguiçoso do `transformers` 5, que passa a procurar a
   versão de um pacote inexistente. Instalar o wheel `+cpu` é a saída certa.

`verificar()` confere tudo isso em tempo de execução; `./falar.py checar` é a
porta de entrada para o diagnóstico. Ver docs/adr/0003 e docs/adr/0009.
"""

from __future__ import annotations

import importlib.metadata as md
import os
import platform

import numpy as np
import soundfile as sf
import torch
import torchaudio

# Versões de `transformers` validadas com síntese completa, não só import.
TRANSFORMERS_VALIDADO = ("4.57.6", "5.15.1")


# --- 1. isin_mps_friendly, removido no transformers 5 ----------------------


def _isin_mps_friendly(elements: torch.Tensor, test_elements) -> torch.Tensor:
    # Sem argumentos nomeados: ver pytorch/pytorch#126045.
    return torch.isin(elements, test_elements)


def _repor_isin_mps_friendly() -> None:
    import transformers.pytorch_utils as pu

    if not hasattr(pu, "isin_mps_friendly"):
        pu.isin_mps_friendly = _isin_mps_friendly


# --- 2. IO de áudio via soundfile ------------------------------------------


def _load(caminho, frame_offset=0, num_frames=-1, normalize=True, channels_first=True, **_):
    dados, taxa = sf.read(
        str(caminho),
        start=frame_offset,
        frames=num_frames if num_frames and num_frames > 0 else -1,
        dtype="float32",
        always_2d=True,
    )
    tensor = torch.from_numpy(np.ascontiguousarray(dados.T if channels_first else dados))
    return tensor, taxa


def _save(caminho, src, sample_rate, channels_first=True, **_):
    dados = src.detach().cpu().numpy()
    if dados.ndim == 1:
        dados = dados[:, None]
    elif channels_first:
        dados = dados.T
    sf.write(str(caminho), dados, sample_rate)


def _info(caminho, **_):
    meta = sf.info(str(caminho))

    class _Info:
        sample_rate = meta.samplerate
        num_frames = meta.frames
        num_channels = meta.channels

    return _Info()


def _io_por_soundfile() -> None:
    torchaudio.load = _load
    torchaudio.save = _save
    torchaudio.info = _info


# --- Entrada única ---------------------------------------------------------


def aplicar() -> None:
    """Aplica as correções. Idempotente; chame antes de importar `TTS`."""
    _repor_isin_mps_friendly()
    _io_por_soundfile()


# --- Diagnóstico -----------------------------------------------------------


def _versao(pacote: str) -> str | None:
    try:
        return md.version(pacote)
    except md.PackageNotFoundError:
        return None


def verificar() -> list[tuple[bool, str, str]]:
    """
    Confere que as correções estão ativas e que o ambiente é o esperado.

    Devolve uma lista de `(ok, item, detalhe)`; `ok=False` marca o que impede a
    síntese de funcionar. Pressupõe que `aplicar()` já rodou — importar
    `vozclone` faz isso. Leva alguns segundos: sobe o `torchcodec` e o `TTS`
    de propósito, para que a checagem seja do ambiente real e não de metadados.
    """
    checagens: list[tuple[bool, str, str]] = []

    # PyTorch CPU-only: a premissa de todo o resto (ADR-0002).
    checagens.append((
        torch.version.cuda is None,
        "PyTorch CPU-only",
        f"torch {torch.__version__}"
        + ("" if torch.version.cuda is None else f" — build CUDA {torch.version.cuda}, inesperado"),
    ))

    # Correção 1: símbolo presente, nativo ou reposto.
    import transformers
    import transformers.pytorch_utils as pu

    tem_isin = hasattr(pu, "isin_mps_friendly")
    reposto = getattr(pu, "isin_mps_friendly", None) is _isin_mps_friendly
    validado = transformers.__version__ in TRANSFORMERS_VALIDADO
    checagens.append((
        tem_isin,
        "isin_mps_friendly disponível",
        f"transformers {transformers.__version__}"
        + (" (reposto por compat.py)" if reposto else " (símbolo nativo)")
        + ("" if validado else " — fora das versões validadas: " + ", ".join(TRANSFORMERS_VALIDADO)),
    ))

    # Correção 2: IO redirecionado.
    io_ok = torchaudio.load is _load and torchaudio.save is _save and torchaudio.info is _info
    checagens.append((
        io_ok,
        "IO de áudio por soundfile",
        f"torchaudio {torchaudio.__version__} + soundfile {_versao('soundfile')}"
        if io_ok
        else "patch NÃO aplicado — chame compat.aplicar() antes de importar TTS",
    ))

    # Correção 3: o wheel do torchcodec é o +cpu, e carrega de verdade?
    tc = _versao("torchcodec")
    if tc is None:
        checagens.append((
            False,
            "torchcodec",
            'ausente — o TTS/__init__.py o exige. Instale: uv pip install -r requirements.txt',
        ))
    else:
        try:
            import torchcodec.decoders  # noqa: F401

            checagens.append((True, "torchcodec carrega", f"torchcodec {tc}"))
        except Exception as e:
            # Não é fatal: o IO já é do soundfile. Mas é o wheel errado.
            checagens.append((
                True,
                "torchcodec carrega",
                f"NÃO ({type(e).__name__}) — wheel {tc} ligado a CUDA. "
                "A síntese segue pelo soundfile, mas instale o +cpu: "
                "uv pip install -r requirements.txt",
            ))

    # O teste que resume tudo: o pacote TTS sobe?
    try:
        import TTS  # noqa: F401

        checagens.append((True, "import TTS", f"coqui-tts {TTS.__version__}"))
    except Exception as e:
        checagens.append((False, "import TTS", f"{type(e).__name__}: {e}"))

    checagens.append((
        True,
        "Threads do PyTorch",
        f"{torch.get_num_threads()} de {os.cpu_count()} lógicas "
        f"(cores físicos; ADR-0005)",
    ))

    checagens.append((
        True,
        "Plataforma",
        f"{platform.system()} {platform.machine()}, Python {platform.python_version()}",
    ))

    return checagens
