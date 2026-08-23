"""
Núcleo de clonagem de voz — XTTS-v2 rodando 100% local em CPU.

Uma voz é um arquivo .wav de referência guardado em vozes/<nome>.wav.
A partir dele o modelo sintetiza qualquer texto em pt-BR ou en-US,
sem treinar nada e sem acesso à internet (após o download inicial).

O IO de áudio usa librosa/soundfile em vez de torchaudio: o torchaudio 2.11
moveu load/save para o torchcodec, cujo wheel é compilado contra CUDA e não
carrega sobre um PyTorch CPU-only (ver audio_io.py e docs/adr/0003).
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from pathlib import Path

# Aceite da Coqui Public Model License (uso não comercial). Depois do
# download inicial dos pesos, nada mais sai da máquina.
os.environ.setdefault("COQUI_TOS_AGREED", "1")

# Corrige o IO de áudio antes de tocar no TTS (ver audio_io.py).
import audio_io

audio_io.aplicar()

# Threads = cores físicos. Hyperthreading degrada muito este modelo: num
# i7-8565U (4 cores / 8 threads), usar 8 threads mediu 2,5x MAIS LENTO que 4.
def _cores_fisicos() -> int:
    try:
        irmaos = Path("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list").read_text()
        por_core = len(irmaos.replace("-", ",").split(","))
        return max(1, (os.cpu_count() or 2) // por_core)
    except OSError:
        return max(1, (os.cpu_count() or 2) // 2)


import torch

torch.set_num_threads(_cores_fisicos())

RAIZ = Path(__file__).resolve().parent
DIR_VOZES = RAIZ / "vozes"
DIR_SAIDA = RAIZ / "saida"
MODELO = "tts_models/multilingual/multi-dataset/xtts_v2"

TAXA = 22050
IDIOMAS = {"pt-br": "pt", "en-us": "en"}

# Referências curtas demais produzem timbre instável; longas demais só
# desperdiçam tempo de encoding sem ganho de similaridade.
REF_MIN_SEG = 6.0
REF_MAX_SEG = 30.0


@dataclass
class Resultado:
    caminho: Path
    duracao_audio: float
    tempo_geracao: float

    @property
    def fator_tempo_real(self) -> float:
        """Segundos de CPU por segundo de áudio. Abaixo de 1.0 é tempo real."""
        return self.tempo_geracao / self.duracao_audio if self.duracao_audio else 0.0


def listar_vozes() -> list[str]:
    return sorted(p.stem for p in DIR_VOZES.glob("*.wav"))


def caminho_voz(nome: str) -> Path:
    caminho = DIR_VOZES / f"{nome}.wav"
    if not caminho.exists():
        disponiveis = ", ".join(listar_vozes()) or "nenhuma"
        raise FileNotFoundError(f"Voz '{nome}' não existe. Cadastradas: {disponiveis}")
    return caminho


def duracao(caminho: str | Path) -> float:
    import soundfile as sf

    info = sf.info(str(caminho))
    return info.frames / info.samplerate


def cadastrar_voz(nome: str, audio_origem: str | Path) -> Path:
    """Converte o áudio para o formato que o XTTS espera: mono, 22.05 kHz."""
    import librosa
    import soundfile as sf

    origem = Path(audio_origem)
    if not origem.exists():
        raise FileNotFoundError(f"Áudio não encontrado: {origem}")

    # librosa resolve conversão de formato, mono e resample de uma vez.
    onda, _ = librosa.load(str(origem), sr=TAXA, mono=True)

    segundos = len(onda) / TAXA
    if segundos < REF_MIN_SEG:
        raise ValueError(
            f"Referência de {segundos:.1f}s é curta demais — use pelo menos {REF_MIN_SEG:.0f}s."
        )
    if segundos > REF_MAX_SEG:  # corta o excesso em vez de recusar
        onda = onda[: int(REF_MAX_SEG * TAXA)]

    # Normaliza o volume para que referências gravadas baixo não degradem o timbre.
    pico = float(abs(onda).max())
    if pico > 0:
        onda = onda / pico * 0.95

    DIR_VOZES.mkdir(parents=True, exist_ok=True)
    destino = DIR_VOZES / f"{nome}.wav"
    sf.write(str(destino), onda, TAXA, subtype="PCM_16")
    return destino


_modelo = None
_quantizado = False


def carregar_modelo(rapido: bool = False):
    """
    Carrega o XTTS-v2 uma única vez por processo (leva ~25s em CPU).

    Com rapido=True aplica quantização dinâmica int8 nas camadas Linear do GPT
    autoregressivo, que é o gargalo. Mediu ~20% mais rápido neste hardware, ao
    custo de alguma perda de fidelidade — compare ouvindo antes de adotar.
    """
    global _modelo, _quantizado
    if _modelo is None:
        from TTS.api import TTS

        _modelo = TTS(MODELO, progress_bar=False)

    if rapido and not _quantizado:
        import torch

        modelo_xtts = _modelo.synthesizer.tts_model
        modelo_xtts.gpt = torch.quantization.quantize_dynamic(
            modelo_xtts.gpt, {torch.nn.Linear}, dtype=torch.qint8
        )
        _quantizado = True
    return _modelo


def sintetizar(
    texto: str,
    voz: str,
    idioma: str = "pt-br",
    saida: str | Path | None = None,
    velocidade: float = 1.0,
    rapido: bool = False,
) -> Resultado:
    if idioma not in IDIOMAS:
        raise ValueError(f"Idioma '{idioma}' inválido. Use: {', '.join(IDIOMAS)}")
    texto = texto.strip()
    if not texto:
        raise ValueError("Texto vazio.")

    referencia = caminho_voz(voz)

    if saida is None:
        DIR_SAIDA.mkdir(parents=True, exist_ok=True)
        saida = DIR_SAIDA / f"{voz}-{idioma}-{int(time.time())}.wav"
    saida = Path(saida)
    saida.parent.mkdir(parents=True, exist_ok=True)

    modelo = carregar_modelo(rapido)
    inicio = time.perf_counter()
    modelo.tts_to_file(
        text=texto,
        file_path=str(saida),
        speaker_wav=str(referencia),
        language=IDIOMAS[idioma],
        speed=velocidade,
        split_sentences=True,  # essencial em CPU: textos longos travam sem isso
    )
    tempo = time.perf_counter() - inicio

    return Resultado(saida, duracao(saida), tempo)
