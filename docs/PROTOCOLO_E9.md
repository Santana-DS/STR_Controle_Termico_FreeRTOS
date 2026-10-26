# Protocolo E9 — custo da instrumentação

## Objetivo

Quantificar separadamente o custo observado dos mecanismos usados para medir
o próprio sistema. O E9 não acessa ADC, não configura PWM e mantém GPIO 25 e
GPIO 26 em nível baixo durante toda a execução.

## Operações medidas

Cada resultado é obtido em 300 lotes. O tempo de um lote é dividido pelo
número de operações executadas, reduzindo o efeito da resolução de 1 us do
`esp_timer`.

| Operação | Conteúdo |
|---|---|
| `BASELINE_LCG` | operação inteira mínima usada como referência |
| `ESP_TIMER_PAIR` | duas leituras consecutivas do relógio |
| `TRACE_BUILD` | construção, cópia e consumo de um registro temporal |
| `QUEUE_SEND_RECEIVE` | envio e retirada sem bloqueio de uma fila |
| `QUEUE_FULL_FAIL` | tentativa não bloqueante quando a fila está cheia |
| `CRITICAL_COUNTER` | incremento protegido por seção crítica |
| `SNPRINTF_TRACE` | formatação textual semelhante ao trace serial |
| `TRACE_PIPELINE` | timestamp, registro, fila e contador combinados |

O resultado apresenta média, P50, P95, P99 e máximo observado. São medições
experimentais no cenário descrito, não limites formais de WCET.

## Procedimento

Com os atuadores desabilitados, cada operação foi executada em 300 lotes. O
tempo total de cada lote foi dividido pelo número de operações e resumido por
média, percentis e máximo.

## Critérios de aprovação

- oito operações recebidas na ordem especificada;
- 300 lotes válidos por operação;
- valores finitos e percentis ordenados;
- término normal;
- saídas físicas mantidas em zero.

## Resultado observado

O ensaio `E9` apresentou oito operações, 300 lotes por
operação, término normal e saídas em zero. O pipeline binário combinado teve
custo médio de 5,589 us; a formatação textual, 50,634 us.
