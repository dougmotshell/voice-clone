# Modelo C4 — Clonador de Voz Local

**Versão 1.0**

Arquitetura descrita segundo o [modelo C4](https://c4model.com/) de Simon Brown,
nos níveis 1 (Contexto), 2 (Contêiner) e 3 (Componente). O nível 4 (Código) é
omitido: o sistema tem quatro módulos e o próprio código, comentado, cumpre esse
papel.

Os diagramas usam Mermaid e renderizam no GitHub e em editores compatíveis.

---

## Nível 1 — Contexto

Como o sistema se encaixa no mundo. O ponto central é o que **não** aparece:
não há serviço em nuvem, API externa nem banco de dados remoto no fluxo normal
de operação.

```mermaid
graph TB
    usuario["<b>Usuário</b><br/><i>[Pessoa]</i><br/>Cadastra vozes e<br/>gera narrações"]

    sistema["<b>Clonador de Voz Local</b><br/><i>[Sistema]</i><br/>Aprende um timbre a partir de 6-30s<br/>de áudio e sintetiza texto arbitrário<br/>em pt-BR e en-US. Opera offline."]

    hf["<b>Hugging Face Hub</b><br/><i>[Sistema externo]</i><br/>Hospeda os pesos do XTTS-v2"]

    fs["<b>Filesystem local</b><br/><i>[Sistema externo]</i><br/>Vozes de referência,<br/>áudios gerados e pesos"]

    usuario -->|"grava/envia áudio,<br/>escreve texto"| sistema
    sistema -->|"devolve WAV<br/>com a voz clonada"| usuario
    sistema -.->|"baixa 1,8 GB<br/><b>uma única vez</b><br/>[HTTPS]"| hf
    sistema -->|"lê e grava<br/>arquivos WAV"| fs

    classDef pessoa fill:#0b4884,stroke:#073b6f,color:#fff
    classDef foco fill:#1168bd,stroke:#0b4884,color:#fff
    classDef externo fill:#666,stroke:#444,color:#fff
    class usuario pessoa
    class sistema foco
    class hf,fs externo
```

A linha tracejada para o Hugging Face é o **único** acesso à rede, e acontece
apenas no primeiro uso. Depois disso o sistema funciona com a máquina
desconectada.

---

## Nível 2 — Contêiner

As unidades executáveis e os depósitos de dados. "Contêiner" aqui é a unidade de
execução do C4, não um contêiner Docker — todos rodam como processos locais.

```mermaid
graph TB
    usuario["<b>Usuário</b><br/><i>[Pessoa]</i>"]

    subgraph sistema["Clonador de Voz Local"]
        cli["<b>CLI</b><br/><i>[Processo Python — falar.py]</i><br/>Subcomandos cadastrar, vozes e falar.<br/>Automação e lotes."]
        web["<b>Interface Web</b><br/><i>[Processo Python — web.py, Gradio]</i><br/>127.0.0.1:7860. Grava pelo microfone e<br/>mantém o modelo residente."]
        nucleo["<b>Núcleo de Voz</b><br/><i>[Módulo Python — vozclone.py]</i><br/>Cadastro, síntese e otimizações de CPU.<br/>Toda a regra vive aqui."]
        motor["<b>Motor XTTS-v2</b><br/><i>[coqui-tts + PyTorch CPU]</i><br/>Inferência zero-shot"]

        vozes[("<b>vozes/</b><br/><i>[WAV mono 22.05 kHz]</i><br/>Referências — <b>dado biométrico</b>")]
        saida[("<b>saida/</b><br/><i>[WAV]</i><br/>Áudios gerados")]
        pesos[("<b>~/.local/share/tts</b><br/><i>[1,8 GB]</i><br/>Pesos do modelo")]
    end

    usuario -->|"linha de comando"| cli
    usuario -->|"navegador<br/>[HTTP local]"| web
    cli -->|"importa"| nucleo
    web -->|"importa"| nucleo
    nucleo -->|"tts_to_file()"| motor
    nucleo -->|"lê referência"| vozes
    nucleo -->|"grava resultado"| saida
    motor -->|"carrega"| pesos

    classDef pessoa fill:#0b4884,stroke:#073b6f,color:#fff
    classDef cont fill:#438dd5,stroke:#2e6295,color:#fff
    classDef dados fill:#8a7f5c,stroke:#6b6248,color:#fff
    class usuario pessoa
    class cli,web,nucleo,motor cont
    class vozes,saida,pesos dados
```

O desenho é deliberadamente simples: **as interfaces são casca fina sobre o
núcleo**. Nem a CLI nem a web contêm regra de negócio, o que permite adicionar
uma terceira interface sem tocar na lógica ([ADR-0007](../adr/0007-interfaces-cli-e-web.md)).

---

## Nível 3 — Componente (Núcleo de Voz)

O interior de `vozclone.py` e suas dependências diretas.

```mermaid
graph TB
    cli["<b>CLI</b> / <b>Web</b><br/><i>[chamadores]</i>"]

    subgraph nucleo["Núcleo de Voz — vozclone.py"]
        bootstrap["<b>Bootstrap de ambiente</b><br/>Aceita a CPML, aplica as correções<br/>e fixa as threads nos cores físicos.<br/><i>Executa no import — a ordem importa.</i>"]
        cadastro["<b>Cadastro de vozes</b><br/><i>cadastrar_voz, listar_vozes, caminho_voz</i><br/>Converte para mono 22.05 kHz, valida<br/>a duração (6-30s) e normaliza o volume."]
        sintese["<b>Síntese</b><br/><i>sintetizar</i><br/>Valida entrada, resolve a saída,<br/>quebra em frases e mede o tempo."]
        modelo["<b>Gestão do modelo</b><br/><i>carregar_modelo</i><br/>Singleton por processo.<br/>Quantização int8 opcional."]
        resultado["<b>Resultado</b><br/><i>[dataclass]</i><br/>caminho, duração, tempo<br/>e fator de tempo real."]
        validacao["<b>Validação de nome</b><br/><i>validar_nome</i><br/>Regras de nome de arquivo do<br/>sistema mais restritivo dos três."]
    end

    io["<b>compat.py</b><br/><i>[correções + diagnóstico]</i><br/>Substitui load/save/info do torchaudio<br/>por soundfile, repõe isin_mps_friendly<br/>e expõe verificar()."]
    ext["<b>librosa</b> / <b>soundfile</b><br/><i>[IO e resample]</i>"]
    tts["<b>coqui-tts</b> → <b>XTTS-v2</b><br/><i>[PyTorch CPU]</i>"]

    cli --> cadastro
    cli --> sintese
    cli -->|"checar /<br/>aba Ambiente"| io
    cadastro --> validacao
    sintese --> validacao
    bootstrap -.->|"aplica antes<br/>de importar TTS"| io
    cadastro --> ext
    sintese --> modelo
    sintese --> resultado
    sintese --> ext
    modelo --> tts
    tts -->|"torchaudio.load<br/>(interceptado)"| io
    io --> ext

    classDef comp fill:#85bbf0,stroke:#5d82a8,color:#000
    classDef libs fill:#999,stroke:#6b6b6b,color:#fff
    class bootstrap,cadastro,sintese,modelo,resultado,validacao comp
    class io,ext,tts libs
```

Três pontos merecem atenção nesse nível.

**O bootstrap executa no import e tem ordem obrigatória.** A CPML é aceita, o
patch de IO é aplicado e as threads são fixadas *antes* de `TTS` ser importado.
Inverter essa ordem faz a clonagem falhar com um erro de biblioteca compartilhada
([ADR-0003](../adr/0003-io-audio-via-soundfile.md)).

**A seta de volta do XTTS para o `compat`** é o que justifica o patch existir:
o motor chama `torchaudio.load` internamente para ler a voz de referência, e é
exatamente essa chamada que estava quebrada.

**A seta direta das interfaces para o `compat`** é o diagnóstico: `verificar()`
confere, em tempo de execução, que os patches estão ativos e que os wheels
certos foram instalados. É o que `falar.py checar` e a aba "Ambiente" da web
expõem, e torna explícito um acoplamento que antes era só convenção.

---

## Fluxos principais

### Cadastro de uma voz

```mermaid
sequenceDiagram
    actor U as Usuário
    participant I as CLI / Web
    participant N as Núcleo
    participant L as librosa/soundfile
    participant D as vozes/

    U->>I: áudio de referência + nome
    I->>N: cadastrar_voz(nome, arquivo)
    N->>L: load(sr=22050, mono=True)
    L-->>N: forma de onda
    N->>N: valida 6-30s, corta excesso
    N->>N: normaliza pico em 0,95
    N->>D: grava <nome>.wav (PCM 16)
    N-->>I: caminho do arquivo
    I-->>U: "Voz cadastrada"
```

A conversão acontece **uma vez, no cadastro**. A partir daí toda referência
guardada já está no formato que o motor espera.

### Síntese de fala

```mermaid
sequenceDiagram
    actor U as Usuário
    participant I as CLI / Web
    participant N as Núcleo
    participant M as XTTS-v2
    participant D as saida/

    U->>I: texto + voz + idioma
    I->>N: sintetizar(...)
    N->>N: valida idioma e texto
    N->>N: resolve a referência
    alt modelo ainda não carregado
        N->>M: carrega pesos (~24 s)
        opt modo rápido
            N->>M: quantiza o GPT em int8
        end
    end
    N->>M: tts_to_file(split_sentences=True)
    M->>M: codifica o timbre da referência
    loop cada frase
        M->>M: GPT autoregressivo → tokens
        M->>M: decodifica em forma de onda
    end
    M->>D: grava o WAV
    N->>N: mede duração e tempo
    N-->>I: Resultado
    I-->>U: áudio + métricas
```

A quebra em frases (`split_sentences=True`) não é cosmética: sem ela, textos
longos consomem memória de forma insustentável em CPU.

---

## Decisões relacionadas

| Elemento do diagrama | ADR |
|---|---|
| Motor XTTS-v2 | [0001](../adr/0001-motor-tts-xtts-v2.md) |
| PyTorch CPU-only | [0002](../adr/0002-pytorch-cpu-only.md) |
| `compat.py` — IO de áudio | [0003](../adr/0003-io-audio-via-soundfile.md) |
| `compat.py` — `isin_mps_friendly` | [0009](../adr/0009-transformers-5-por-reposicao-de-simbolo.md) |
| Validação de nome, detecção de cores | [0010](../adr/0010-portabilidade-tres-plataformas.md) |
| Bootstrap — threads | [0005](../adr/0005-threads-cores-fisicos.md) |
| Gestão do modelo — int8 | [0006](../adr/0006-quantizacao-int8-opcional.md) |
| CLI e Web | [0007](../adr/0007-interfaces-cli-e-web.md) |
| `vozes/` no filesystem | [0008](../adr/0008-vozes-como-arquivos-locais.md) |
