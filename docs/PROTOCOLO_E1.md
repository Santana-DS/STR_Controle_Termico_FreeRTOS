# Ensaio E1 — temporização da arquitetura FreeRTOS

## Objetivo

Avaliar tarefas, precedências, filas, jitter e deadlines durante 1.800 s, com
entrada térmica e atuação simuladas e a fonte de 12 V desligada.

## Comandos

| Comando | Resposta | Efeito |
|---|---|---|
| `PING` | `ACK,PONG,E1_TIMING` | identifica o runner |
| `START` | `ACK,START` | zera filas e contadores e libera a aquisição |
| `STOP` | `ACK,STOP` | envia evento esporádico à supervisão |
| `STATUS` | `STATUS,...` | informa estado, filas e descartes |

## Trace

Cada registro começa por `TRACE` e contém:

| Campo | Unidade | Definição |
|---|---:|---|
| `task` | — | tarefa ou caminho instrumentado |
| `seq` | — | sequência local do job |
| `release_us` | µs | liberação nominal ou instante do evento |
| `start_us` | µs | início efetivo |
| `finish_us` | µs | término efetivo |
| `deadline_us` | µs | deadline local |
| `jitter_us` | µs | `start - release` |
| `exec_us` | µs | `finish - start` |
| `response_us` | µs | `finish - release` |
| `miss` | lógico | resposta local acima do deadline |
| `e2e_us` | µs | resposta desde a aquisição ou evento `STOP` |
| `e2e_deadline_us` | µs | deadline fim a fim aplicável |
| `e2e_miss` | lógico | resposta fim a fim acima do deadline |
| `q_trace` | itens | ocupação observada da fila de trace |
| `drops` | itens | descartes acumulados de trace |

`exec_us` mede o trecho executado entre os pontos de instrumentação. No E1 a
aquisição é sintética; logo, esse valor não representa o custo do ADC físico.
A série periódica da supervisão é ancorada no primeiro job observado pelo
`esp_timer`; eventuais antecipações submicrossegundo causadas pela conversão
do tick são limitadas a jitter zero, nunca registradas como tempo negativo.

## Critérios de aceitação

1. runner identificado corretamente;
2. pelo menos um job de cada caminho periódico e da cadeia de controle;
3. nenhuma perda de deadline local;
4. nenhuma perda do deadline fim a fim;
5. nenhum descarte de trace;
6. sequências contínuas e coerentes entre aquisição, controle e atuação.

## Resultado observado

Foram registrados 4.551 eventos: 315 aquisições, 315 controles, 315 atuações
e 3.604 execuções da supervisão. Não ocorreram perdas de deadline nem
descartes. A resposta fim a fim máxima foi 622 us diante do limite de
5.715.000 us.
