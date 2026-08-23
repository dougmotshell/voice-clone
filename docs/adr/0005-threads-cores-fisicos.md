# ADR-0005 — Limitar threads aos cores físicos

**Status:** Aceito · **Data:** 2026-08-23

## Contexto

A máquina-alvo tem 4 cores físicos e 8 threads lógicas (hyperthreading). O
PyTorch, por padrão, já usava 4 threads. A hipótese natural era que subir para 8
aproveitaria melhor a CPU.

A medição, com a mesma frase e a mesma voz de referência, mostrou o contrário:

| Threads | Tempo de geração | Fator |
|---|---|---|
| 4 | **21,4 s** | 4,01x |
| 8 | 54,3 s | 10,17x |

Usar as threads lógicas foi **2,5x mais lento**. O padrão provável é contenção:
as duas threads lógicas de um mesmo core físico competem pelas mesmas unidades
de execução vetorial (AVX) e pelo cache L1/L2, e as operações de GEMM do modelo
saturam justamente esses recursos. O overhead de sincronização entre 8 workers
supera qualquer ganho.

## Decisão

Fixar `torch.set_num_threads()` no número de **cores físicos**, detectado a
partir de `/sys/devices/system/cpu/cpu0/topology/thread_siblings_list`, com
fallback para `os.cpu_count() // 2` caso o arquivo não exista.

A configuração é aplicada na importação de `vozclone.py`, de modo que CLI, web e
uso como biblioteca herdam o mesmo comportamento.

## Consequências

**Positivas**
- 2,5x de desempenho em relação ao uso ingênuo das threads lógicas.
- Detecção automática: funciona em outras máquinas sem ajuste manual.

**Negativas**
- Sobrescreve a configuração global do PyTorch no processo. Um script que
  importe `vozclone` e faça outro trabalho em PyTorch herda esse limite.
- A heurística assume topologia homogênea. Em CPUs híbridas (P-cores e E-cores),
  a contagem pode não ser a ideal, embora ainda seja melhor que o total lógico.
- O número não é configurável por parâmetro. Quem precisar ajustar deve chamar
  `torch.set_num_threads()` após importar `vozclone`.

## Notas

Medição feita com governor `powersave`. Com `performance`, os números absolutos
melhoram, mas a relação entre 4 e 8 threads deve se manter.

## Revisão — 2026-08-23

A leitura de `/sys/devices/system/cpu/cpu0/topology/thread_siblings_list` só
existe no Linux. A detecção passou a usar `psutil.cpu_count(logical=False)`, que
responde nas três plataformas, com `/sys` e `sysctl` como recuos e a divisão por
dois em último lugar — em CPUs sem SMT ela erraria por metade. Ver
[ADR-0010](0010-portabilidade-tres-plataformas.md).
