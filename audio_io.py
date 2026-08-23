"""
Redireciona o IO do torchaudio para soundfile/librosa.

A partir do torchaudio 2.9 o load/save delega ao torchcodec, e o wheel do
torchcodec é compilado contra CUDA (libcudart, libtorch_cuda) — ele não carrega
em cima de um PyTorch CPU-only. Como o XTTS chama torchaudio.load internamente
para ler o áudio de referência, sem este patch a clonagem quebra.

Importe este módulo ANTES de qualquer import de TTS.
"""

from __future__ import annotations

import numpy as np
import soundfile as sf
import torch
import torchaudio


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


def aplicar() -> None:
    torchaudio.load = _load
    torchaudio.save = _save
    torchaudio.info = _info
