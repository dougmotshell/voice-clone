# ADR-0007 — Duas interfaces: CLI e web local

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

Carregar o XTTS-v2 leva ~24 s, um custo fixo por processo. Isso molda a
usabilidade: numa CLI, cada invocação paga os 24 s, o que é tolerável para um
lote grande e péssimo para experimentação iterativa.

Havia ainda uma necessidade prática não coberta por CLI: **capturar a voz de
referência**. Gravar áudio pelo terminal exige ferramentas externas
(`arecord`, `sox`) e conhecimento de parâmetros de captura.

## Decisão

Entregar duas interfaces sobre o mesmo núcleo (`vozclone.py`):

- **`falar.py`** — CLI com os subcomandos `cadastrar`, `vozes` e `falar`. Serve
  automação, scripts e processamento em lote.
- **`web.py`** — interface Gradio, servida em `127.0.0.1:7860`. Mantém o modelo
  residente entre gerações e permite **gravar a referência pelo microfone do
  navegador**.

O Gradio foi escolhido por já resolver upload de arquivo, captura de microfone e
player de áudio sem código de frontend, e por ser dependência leve num ambiente
que já carrega PyTorch.

O servidor escuta explicitamente em `127.0.0.1`, nunca em `0.0.0.0`, e o
compartilhamento remoto do Gradio (`share=True`) **não** é usado: expor um
serviço que processa dados biométricos por túnel público contrariaria o requisito
de operação local ([ADR-0008](0008-vozes-como-arquivos-locais.md)).

## Consequências

**Positivas**
- Cada modo de uso é atendido pela interface adequada.
- A captura por microfone remove a maior barreira de entrada do sistema.
- Toda a lógica vive no núcleo; as interfaces são casca fina.

**Negativas**
- Duas superfícies de interface para manter em sincronia. Uma opção nova precisa
  ser exposta nas duas (ocorreu com o modo rápido do [ADR-0006](0006-quantizacao-int8-opcional.md)).
- O Gradio adiciona um servidor web e suas dependências a um sistema que, no
  essencial, é offline.
- A interface web é monousuário por natureza: gerações concorrentes disputam o
  mesmo modelo e a mesma CPU.
