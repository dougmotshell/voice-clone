# Manual do Clonador de Voz Local

**Versão 1.0**

Manual de operação do sistema de clonagem de voz. Para as decisões de
arquitetura, veja o [SDD](SDD.md), os [ADRs](adr/) e o [modelo C4](c4/).

---

## 1. O que o sistema faz

A partir de **6 a 30 segundos** de fala gravada, o sistema aprende o timbre de
uma voz e passa a sintetizar **qualquer texto** naquela voz, em **português do
Brasil** e **inglês americano**.

Roda **inteiramente na sua máquina**, sem GPU, sem custo e sem internet — o
único acesso à rede é o download inicial dos pesos do modelo (1,8 GB), feito uma
única vez.

Não há treinamento: a clonagem é *zero-shot*, ou seja, o modelo extrai as
características da voz na hora, a cada síntese.

---

## 2. Antes de começar

### Requisitos

Já estão satisfeitos no ambiente instalado em `~/www/voice-clone`:

- Linux com Python 3.12
- ~3,5 GB de disco (1,7 GB de ambiente + 1,8 GB de pesos)
- 4 GB de RAM livres durante a execução
- Nenhuma GPU necessária

### Preparando o áudio de referência

A qualidade da clonagem depende mais do áudio de referência do que de qualquer
ajuste no sistema. Um bom material de referência tem:

| Característica | Recomendação |
|---|---|
| Duração | 15–20 s é o ponto ideal (mínimo 6 s, máximo 30 s) |
| Conteúdo | Fala contínua e natural, em frases completas |
| Ruído | Nenhum. Sem música, sem eco, sem outras vozes |
| Formato | WAV, MP3 ou FLAC — a conversão é automática |
| Gravação | Ambiente fechado, microfone a uma distância constante |

O que **degrada** o resultado: sussurro, grito, fala muito rápida, cortes
abruptos, compressão agressiva de MP3, e trechos com silêncio longo.

O sistema recusa áudios com menos de 6 s e corta automaticamente o que passar de
30 s. Ele também converte tudo para mono a 22.050 Hz e normaliza o volume, então
não é preciso preparar o arquivo manualmente.

---

## 3. Uso pela interface web (recomendado)

A interface web é mais confortável para uso repetido, porque mantém o modelo
carregado na memória entre as gerações — você paga os ~24 s de carga uma vez só.

```bash
cd ~/www/voice-clone
.venv/bin/python web.py
```

Abra `http://127.0.0.1:7860` no navegador. O servidor escuta **apenas em
localhost**: não fica exposto na rede.

**Aba "1. Cadastrar voz"** — dê um nome à voz, grave pelo microfone ou envie um
arquivo, e clique em *Cadastrar voz*. A voz passa a aparecer na segunda aba.

**Aba "2. Falar"** — selecione a voz, escreva o texto, escolha o idioma e clique
em *Gerar áudio*. O player aparece logo abaixo, junto com o tempo que a geração
levou.

Para encerrar, `Ctrl+C` no terminal.

---

## 4. Uso pela linha de comando

Útil para automação, lotes e scripts. Cada execução recarrega o modelo (~24 s),
então prefira gerar textos longos de uma vez em vez de muitas chamadas curtas.

### Cadastrar uma voz

```bash
.venv/bin/python falar.py cadastrar douglas ~/audios/minha-voz.wav
```

O nome (`douglas`) é como você vai se referir à voz depois. Cadastrar de novo
com o mesmo nome substitui a referência anterior.

### Listar vozes

```bash
.venv/bin/python falar.py vozes
```

### Gerar áudio

```bash
# português (padrão)
.venv/bin/python falar.py falar douglas "Olá, este é um teste."

# inglês
.venv/bin/python falar.py falar douglas "Hello, this is a test." -i en-us

# a partir de um arquivo de texto, com saída definida
.venv/bin/python falar.py falar douglas -f roteiro.txt -o saida/narracao.wav

# um pouco mais rápido na fala, e com o modo rápido de síntese
.venv/bin/python falar.py falar douglas "Texto aqui." -v 1.1 -r
```

### Opções de `falar`

| Opção | Efeito |
|---|---|
| `-i`, `--idioma` | `pt-br` (padrão) ou `en-us` |
| `-f`, `--arquivo` | Lê o texto de um `.txt` em vez do argumento |
| `-o`, `--saida` | Caminho do WAV gerado (padrão: `saida/<voz>-<idioma>-<timestamp>.wav`) |
| `-v`, `--velocidade` | 0.6 a 1.4 — ritmo da fala (padrão 1.0) |
| `-r`, `--rapido` | Quantização int8: ~20% mais rápido, leve perda de fidelidade |

---

## 5. Uso como biblioteca Python

```python
from vozclone import cadastrar_voz, sintetizar, listar_vozes

cadastrar_voz("douglas", "/caminho/audio.wav")

r = sintetizar("Texto a ser falado.", voz="douglas", idioma="pt-br")
print(r.caminho, r.duracao_audio, r.tempo_geracao, r.fator_tempo_real)
```

Em scripts que geram vários áudios, chame `carregar_modelo()` uma vez no início:
as chamadas seguintes de `sintetizar` reaproveitam o modelo já em memória.

---

## 6. O que esperar de desempenho

Medido em Intel i7-8565U (4 cores, sem GPU), governor `powersave`:

| Tarefa | Tempo |
|---|---|
| Carga do modelo (uma vez por processo) | ~24 s |
| Frase curta (~5 s de áudio) | ~21 s — ou ~17 s com `-r` |
| Parágrafo (~14 s de áudio) | ~56 s |

Na prática: **3 a 4 segundos de processamento por segundo de áudio gerado**.

Isso **não é tempo real** e não há como torná-lo tempo real sem GPU. O sistema
foi feito para geração em lote — narração, roteiros, testes — e não para
conversação ao vivo.

### Como acelerar

1. **Use a interface web** para trabalho repetido: economiza os 24 s de carga
   a cada geração.
2. **Ative o modo rápido** (`-r` ou o checkbox) se a perda de fidelidade for
   aceitável para o seu caso. Compare ouvindo os dois antes de decidir.
3. **Mude o governor da CPU** para `performance` (requer sudo):
   ```bash
   sudo cpupower frequency-set -g performance
   ```
4. **Não aumente o número de threads.** Já está fixado nos 4 cores físicos.
   Usar as 8 threads lógicas mede 2,5x **mais lento** neste modelo.

---

## 7. Solução de problemas

**"Referência de X s é curta demais"** — o áudio tem menos de 6 s. Grave mais.

**"Voz 'nome' não existe"** — rode `falar.py vozes` para ver os nomes
cadastrados. O nome diferencia maiúsculas de minúsculas.

**A voz gerada não se parece com a original** — quase sempre é o áudio de
referência. Regrave com 15–20 s de fala contínua e limpa. Se estiver usando o
modo rápido, teste sem ele.

**A pronúncia sai errada em nomes próprios ou siglas** — escreva foneticamente
no texto de entrada (`"A P I"` em vez de `"API"`). O modelo não tem dicionário
de exceções.

**Parece travado em textos longos** — não está: o modelo processa frase a frase.
Um parágrafo leva perto de um minuto. Acompanhe pelo terminal.

**`OSError: Could not load this library: libtorchcodec_image.so`** — o patch de
IO de áudio não foi aplicado. Isso acontece se algum código importar `TTS` antes
de `vozclone`. Sempre importe `vozclone` primeiro (ver [ADR-0003](adr/0003-io-audio-via-soundfile.md)).

**`ImportError: cannot import name 'isin_mps_friendly'`** — o `transformers`
subiu para a série 5.x. Reinstale com `uv pip install "transformers<5"`
(ver [ADR-0004](adr/0004-fixar-transformers-4x.md)).

**Sem espaço em disco** — os pesos ficam em `~/.local/share/tts` (1,8 GB) e o
ambiente em `~/www/voice-clone/.venv` (1,7 GB). Os áudios gerados se acumulam em
`saida/` e podem ser apagados à vontade.

---

## 8. Limites conhecidos

- **Dois idiomas apenas** nesta configuração (pt-BR e en-US), embora o XTTS-v2
  suporte 17. Foi uma restrição de escopo, não do modelo.
- **Sem controle de emoção** — o tom vem do áudio de referência. Uma referência
  neutra produz fala neutra.
- **Sem streaming** — o áudio só fica disponível quando a geração termina.
- **Uma voz por síntese** — não há diálogo entre vozes diferentes num mesmo
  arquivo.
- **Não determinístico** — o mesmo texto gera áudios ligeiramente diferentes a
  cada execução.

---

## 9. Uso responsável e segurança da informação

**Consentimento é obrigatório.** Clonar a voz de uma pessoa exige autorização
explícita dela. Não use o sistema para imitar terceiros sem permissão, nem para
produzir conteúdo que se passe por outra pessoa.

**Áudio de voz é dado biométrico.** O conteúdo de `vozes/` deve ser tratado com
o mesmo cuidado de qualquer dado pessoal sensível:

- `vozes/` e `saida/` já estão no `.gitignore` — não versione essas pastas.
- Não envie referências de voz para serviços externos, repositórios
  compartilhados ou canais de chat.
- Remova as referências quando não forem mais necessárias.

**Licença do modelo.** O XTTS-v2 usa a Coqui Public Model License (CPML), que
**proíbe uso comercial**. Esta instalação está configurada para uso pessoal e
experimentação. Para uso comercial seria necessário trocar o motor
(ver [ADR-0001](adr/0001-motor-tts-xtts-v2.md)).

Ao compartilhar áudios gerados ou referências de voz com terceiros, lembre que
áudio de voz é dado biométrico e merece o mesmo cuidado de qualquer dado
pessoal.
