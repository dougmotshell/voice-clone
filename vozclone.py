"""
Núcleo de clonagem de voz — XTTS-v2 rodando 100% local em CPU.

Uma voz é um arquivo .wav de referência guardado em vozes/<nome>.wav.
A partir dele o modelo sintetiza qualquer texto em pt-BR ou en-US,
sem treinar nada e sem acesso à internet (após o download inicial).

As correções de compatibilidade do ecossistema (IO de áudio por soundfile,
torchcodec dispensado, símbolo reposto no transformers 5) ficam em compat.py,
aplicadas antes de qualquer import de TTS. Ver docs/adr/0003 e 0004.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

# Aceite da Coqui Public Model License (uso não comercial). Depois do
# download inicial dos pesos, nada mais sai da máquina.
os.environ.setdefault("COQUI_TOS_AGREED", "1")

# Aplica as correções de compatibilidade antes de tocar no TTS (ver compat.py).
import compat

compat.aplicar()

# Threads = cores físicos. Hyperthreading degrada muito este modelo: num
# i7-8565U (4 cores / 8 threads), usar 8 threads mediu 2,5x MAIS LENTO que 4.
def _cores_fisicos() -> int:
    """
    Conta cores físicos, não threads lógicas (ADR-0005).

    O `psutil` responde isso nas três plataformas e é a via preferida. Os
    recuos cobrem a sua ausência: `/sys` no Linux, `sysctl` no macOS. O último
    recuo assume SMT de duas vias — o arranjo comum em x86 —, e por isso vem
    depois dos específicos: em CPUs sem SMT (Apple Silicon, por exemplo) físico
    e lógico coincidem, e dividir por dois jogaria fora metade da máquina.
    """
    logicos = os.cpu_count() or 2

    try:
        import psutil

        if fisicos := psutil.cpu_count(logical=False):
            return fisicos
    except ImportError:
        pass

    if sys.platform == "linux":
        try:
            irmaos = Path("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list").read_text()
            por_core = len(irmaos.replace("-", ",").split(","))
            return max(1, logicos // por_core)
        except OSError:
            pass
    elif sys.platform == "darwin":
        try:
            saida = subprocess.run(
                ["sysctl", "-n", "hw.physicalcpu"], capture_output=True, text=True, timeout=5
            )
            return max(1, int(saida.stdout.strip()))
        except (OSError, ValueError, subprocess.SubprocessError):
            pass

    return max(1, logicos // 2)


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


# O nome da voz vira nome de arquivo, então precisa passar pelas regras do
# sistema mais restritivo dos três. O Windows recusa estes caracteres, reserva
# alguns nomes de dispositivo e corta ponto ou espaço no fim; as barras
# quebrariam o caminho em qualquer sistema.
_NOME_INVALIDO = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_NOMES_RESERVADOS = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}

# Um rótulo de voz é curto por natureza. O limite existe para que o estouro
# apareça como mensagem em pt-BR em vez de `OSError: [Errno 36] File name too
# long` na hora de gravar — 300 caracteres passavam a validação e quebravam ali.
# 128 fica longe do teto de 255 bytes do componente no Linux e no macOS, e deixa
# folga para os 260 do MAX_PATH no Windows sem long paths habilitados.
NOME_MAX = 128


def validar_nome(nome: str) -> str:
    """Devolve o nome limpo ou levanta ValueError explicando o que está errado."""
    nome = (nome or "").strip()
    if not nome:
        raise ValueError("Informe um nome para a voz.")
    if len(nome) > NOME_MAX:
        raise ValueError(
            f"O nome tem {len(nome)} caracteres; o limite é {NOME_MAX}."
        )
    if _NOME_INVALIDO.search(nome):
        raise ValueError(
            'O nome não pode conter < > : " / \\ | ? * nem caracteres de controle.'
        )
    if nome.rstrip(". ") != nome:
        raise ValueError("O nome não pode terminar em ponto nem em espaço.")
    # A reserva vale com qualquer extensão: no Windows, `CON.wav` continua sendo
    # o dispositivo de console, e gravar ali não produz arquivo nenhum. Por isso
    # a comparação é com o trecho antes do primeiro ponto, não com o nome todo.
    if nome.split(".")[0].upper() in _NOMES_RESERVADOS:
        raise ValueError(f"'{nome}' é um nome reservado pelo Windows. Escolha outro.")
    return nome


def listar_vozes() -> list[str]:
    return sorted(p.stem for p in DIR_VOZES.glob("*.wav"))


def caminho_voz(nome: str) -> Path:
    caminho = DIR_VOZES / f"{validar_nome(nome)}.wav"
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

    nome = validar_nome(nome)
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
        try:
            modelo_xtts.gpt = torch.quantization.quantize_dynamic(
                modelo_xtts.gpt, {torch.nn.Linear}, dtype=torch.qint8
            )
        except (RuntimeError, NotImplementedError) as e:
            # O backend de quantização varia com a arquitetura (fbgemm em x86,
            # qnnpack em ARM). Se faltar, seguir em float32 é melhor que abortar.
            print(f"Aviso: modo rápido indisponível nesta CPU ({e}); seguindo em float32.",
                  file=sys.stderr)
        _quantizado = True  # não insiste a cada chamada
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
