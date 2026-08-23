# ADR-0009 — Compatibilidade com `transformers` 5 por reposição de símbolo

**Status:** Aceito · **Data:** 2026-08-23 · **Substitui:** [ADR-0004](0004-fixar-transformers-4x.md)

## Contexto

O [ADR-0004](0004-fixar-transformers-4x.md) resolveu a quebra do import de `TTS`
fixando `transformers<5`. O diagnóstico continua correto — o XTTS herda o
backbone autoregressivo do Tortoise, que importa
`transformers.pytorch_utils.isin_mps_friendly`, removido na série 5.x:

```
ImportError: cannot import name 'isin_mps_friendly' from 'transformers.pytorch_utils'
```

O que mudou é a avaliação do custo do pin. Ele foi tratado como obrigatório e
inevitável, mas nunca se mediu **quanto** da série 5.x era realmente
incompatível. A revisão mediu: um único símbolo, com uma implementação de duas
linhas.

Levantamento do uso em `coqui-tts 0.27.5`:

```
TTS/tts/layers/tortoise/autoregressive.py:12:
    from transformers.pytorch_utils import isin_mps_friendly as isin
```

Uma ocorrência, um import. E a implementação original em `transformers 4.57.6`
mostra que, fora do Apple MPS com PyTorch antigo, a função é literalmente
`torch.isin`:

```python
if elements.device.type == "mps" and not is_torch_greater_or_equal_than_2_4:
    ...                                  # caminho legado, irrelevante aqui
else:
    return torch.isin(elements, test_elements)
```

## Alternativas avaliadas

1. **Manter `transformers<5`** — funciona, mas prende o projeto a uma série sem
   correções, e uma reinstalação distraída reintroduz a falha em silêncio.
2. **Esperar o `coqui-tts` publicar suporte à 5.x** — sem prazo, e o projeto
   fica parado no pin nesse meio tempo.
3. **Repor o símbolo em `compat.py`** — escolhido.

## Decisão

Repor `isin_mps_friendly` em `transformers.pytorch_utils` quando ele não existir,
dentro de `compat.aplicar()`, antes de qualquer import de `TTS`:

```python
def _isin_mps_friendly(elements, test_elements):
    return torch.isin(elements, test_elements)
```

O pin sai do manifesto, que passa a pedir apenas `transformers>=4.57` — a versão
mínima que o próprio `coqui-tts` exige.

A validação **não foi por import**, e sim por síntese completa: o mesmo texto,
a mesma voz de referência, em dois ambientes idênticos exceto pela série do
`transformers`. As duas geraram áudio íntegro:

| `transformers` | Resultado |
|---|---|
| 4.57.6 | Síntese completa, símbolo nativo |
| 5.15.1 | Síntese completa, símbolo reposto |

As versões validadas estão em `compat.TRANSFORMERS_VALIDADO`, e o comando
`checar` avisa quando o ambiente sai dessa faixa.

## Consequências

**Positivas**
- O projeto acompanha a série corrente do `transformers` e recebe as suas
  correções, em vez de congelar numa linha em fim de vida.
- Uma reinstalação sem pins não reintroduz a falha: não há mais pin a esquecer.
- O ambiente virtual deixa de conflitar com projetos que exijam `transformers>=5`.

**Negativas**
- **É um monkeypatch**, com o mesmo acoplamento do [ADR-0003](0003-io-audio-via-soundfile.md):
  depende de o `coqui-tts` continuar precisando exatamente deste símbolo. Se a
  série 6.x remover outra coisa, aparece um erro novo — que o comando `checar`
  localiza, mas não conserta.
- A cobertura é a de duas versões testadas, não a da série inteira. Daí o aviso
  do `checar` fora da faixa validada.
- No `transformers` 5.15.1 a síntese emite avisos novos sobre `bos_token_id` e
  `eos_token_id` fora do vocabulário. São da configuração do XTTS, aparecem
  também sem o patch e não afetam o áudio gerado — mas poluem a saída.

## Notas

Tentou-se, na mesma revisão, neutralizar a guarda de `torchcodec` do
`TTS/__init__.py` mentindo em `is_torchcodec_available()`. **Não funciona com a
série 5.x**: a máquina de import preguiçoso do `transformers` acredita na
resposta e vai buscar a versão de um pacote que não está instalado, derrubando o
import de `GPT2PreTrainedModel`. O registro fica aqui para poupar a tentativa —
a saída certa é a do [ADR-0003](0003-io-audio-via-soundfile.md).

---
*Classificação ISO/IEC 27001: Uso Interno. Documento técnico sem dados pessoais.*
