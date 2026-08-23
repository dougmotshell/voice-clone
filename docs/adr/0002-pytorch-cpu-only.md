# ADR-0002 — PyTorch em build CPU-only

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

A instalação padrão do PyTorch via PyPI traz as bibliotecas CUDA empacotadas,
somando cerca de 2,5 GB de dependências. A máquina-alvo não tem GPU NVIDIA e
tinha 47 GB livres em disco.

## Decisão

Instalar o PyTorch a partir do índice CPU-only:

```bash
uv pip install --index-url https://download.pytorch.org/whl/cpu torch torchaudio
```

Resultado: `torch 2.13.0+cpu`, 183 MB em vez de ~2,5 GB.

## Consequências

**Positivas**
- Economia de ~2,3 GB de disco e de tempo de download.
- Sem risco de o runtime tentar inicializar CUDA inexistente.

**Negativas**
- **Incompatibilidade com o wheel do `torchcodec`**, que é compilado contra
  CUDA. Este efeito colateral não era previsto e gerou o [ADR-0003](0003-io-audio-via-soundfile.md).
- Migrar para GPU no futuro exige reinstalar o PyTorch com o índice CUDA.

## Notas

A escolha continua correta apesar do efeito colateral: instalar o build CUDA
apenas para satisfazer o `torchcodec` traria 2,3 GB de bibliotecas que nunca
seriam executadas, sem resolver o problema de desempenho.
