# Architecture Decision Records

Registro das decisões de arquitetura do Clonador de Voz Local. Cada ADR captura
uma decisão, o contexto em que foi tomada e as consequências aceitas.

Formato: [Michael Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions.html).
Status possíveis: `Proposto`, `Aceito`, `Substituído por ADR-XXXX`, `Obsoleto`.

| ADR | Título | Status |
|---|---|---|
| [0001](0001-motor-tts-xtts-v2.md) | XTTS-v2 como motor de síntese | Aceito |
| [0002](0002-pytorch-cpu-only.md) | PyTorch em build CPU-only | Aceito |
| [0003](0003-io-audio-via-soundfile.md) | IO de áudio via soundfile, contornando o torchcodec | Aceito |
| [0004](0004-fixar-transformers-4x.md) | Fixar `transformers` na série 4.x | Substituído por ADR-0009 |
| [0005](0005-threads-cores-fisicos.md) | Limitar threads aos cores físicos | Aceito |
| [0006](0006-quantizacao-int8-opcional.md) | Quantização int8 como opção, não padrão | Aceito |
| [0007](0007-interfaces-cli-e-web.md) | Duas interfaces: CLI e web local | Aceito |
| [0008](0008-vozes-como-arquivos-locais.md) | Vozes como arquivos WAV no filesystem | Aceito |
| [0009](0009-transformers-5-por-reposicao-de-simbolo.md) | Compatibilidade com `transformers` 5 por reposição de símbolo | Aceito |
| [0010](0010-portabilidade-tres-plataformas.md) | Suporte a Linux, macOS e Windows | Aceito |
| [0011](0011-instalacao-por-script.md) | Instalação e desinstalação por script | Aceito |

## Decisões pendentes

Registradas para retomada futura, ainda sem ADR:

- **Troca de motor para uso comercial.** A CPML do XTTS-v2 proíbe uso comercial.
  Se o projeto mudar de escopo, avaliar Chatterbox Multilingual (MIT).
- **Cache do latente do falante.** O encoding da referência é refeito a cada
  síntese; cachear pode dar ganho em lotes com a mesma voz.
- **Remoção do patch de IO de áudio.** Com o wheel `+cpu` do `torchcodec`, o
  `torchaudio.load` funciona sem patch. Ele foi mantido pelos motivos da revisão
  do [ADR-0003](0003-io-audio-via-soundfile.md); se o `coqui-tts` parar de
  chamar `torchaudio.info`, vale reavaliar.
- **Medição em macOS e Windows.** A resolução de dependências foi verificada nas
  três plataformas; a síntese, só no Linux.
