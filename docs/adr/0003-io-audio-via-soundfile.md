# ADR-0003 — IO de áudio via soundfile, contornando o torchcodec

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

A partir do PyTorch 2.9, o `torchaudio` deixou de implementar leitura e escrita
de áudio e passou a delegar `load`/`save`/`info` ao pacote `torchcodec`.

Na montagem do ambiente, qualquer operação de IO falhava com:

```
OSError: Could not load this library: .../torchcodec/libtorchcodec_image.so
```

A hipótese inicial — ausência de FFmpeg no sistema — estava **errada**: o
`ffmpeg` e as bibliotecas `libav*` estavam instalados. O `ldd` sobre a biblioteca
revelou a causa real:

```
libcudart.so.13   => not found
libtorch_cuda.so  => not found
libc10_cuda.so    => not found
```

O wheel do `torchcodec 0.16.0` é **compilado contra CUDA** e não carrega sobre um
PyTorch CPU-only ([ADR-0002](0002-pytorch-cpu-only.md)).

Isso não era um detalhe cosmético: o XTTS chama `torchaudio.load` internamente,
em `TTS/tts/models/xtts.py`, justamente para ler o áudio de referência do
falante. Sem IO funcional, **a clonagem de voz não funcionava** — apenas os
speakers pré-embutidos.

## Alternativas avaliadas

1. **Instalar o PyTorch com CUDA** para satisfazer o `torchcodec` — traria 2,3 GB
   de bibliotecas jamais executadas, numa máquina sem GPU. Rejeitado.
2. **Compilar o torchcodec do fonte** contra o PyTorch CPU — viável, mas
   adiciona toolchain de build C++ e fragilidade a cada atualização. Rejeitado.
3. **Fixar `torchaudio` numa versão anterior à 2.9** — resolveria, mas prende o
   projeto a versões antigas e conflita com o `torch 2.13`. Rejeitado.
4. **Redirecionar o IO do torchaudio para `soundfile`** — escolhido.

## Decisão

Criar o módulo `audio_io.py`, que substitui `torchaudio.load`, `torchaudio.save`
e `torchaudio.info` por implementações baseadas em `soundfile`, preservando a
assinatura e o contrato originais (tensor `[canais, amostras]` mais taxa de
amostragem).

O patch é aplicado por `vozclone.py` **antes de qualquer import de `TTS`**, o que
garante que o XTTS use as funções substituídas.

`soundfile` e `librosa` já vinham como dependências do `coqui-tts` — a correção
não adiciona nenhum pacote novo, e o `libsndfile` cobre WAV, FLAC e MP3 sem
depender de FFmpeg.

## Consequências

**Positivas**
- Clonagem de voz funcional com PyTorch CPU-only.
- Zero dependências adicionais.
- Independe do FFmpeg do sistema.

**Negativas**
- **É um monkeypatch**, com o acoplamento que isso implica: se uma versão futura
  do XTTS mudar a forma como chama o `torchaudio`, o patch pode deixar de cobrir
  todos os caminhos.
- **Impõe uma ordem de import**: `vozclone` precisa ser importado antes de `TTS`.
  Um import fora de ordem reintroduz o erro original. Documentado no manual.
- Formatos exóticos suportados pelo FFmpeg mas não pelo `libsndfile` (por
  exemplo, áudio dentro de contêiner de vídeo) deixam de funcionar.

## Notas

Quando o `torchcodec` publicar wheels CPU-only funcionais, este patch pode ser
removido. O teste é simples: remover a chamada `audio_io.aplicar()` e verificar
se `falar.py cadastrar` conclui sem erro.
