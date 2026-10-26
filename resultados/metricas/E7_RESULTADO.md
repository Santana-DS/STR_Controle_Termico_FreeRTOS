# Resultado do ensaio E7

## Configuração

- ESP32 DevKit V1 alimentada apenas por USB;
- fonte de 12 V da planta desligada;
- entrada térmica e atuação simuladas, sem ADC e sem PWM;
- timeout de heartbeat: 15 s;
- período de verificação do watchdog: 5 ms;
- deadline entre vencimento e atuação segura: 50 ms;
- 10 repetições com quatro heartbeats explícitos em cada uma.

## Integridade

O ensaio produziu 459 registros ao longo de aproximadamente 157,38 s:

- 40 registros `HB_RX`, com sequência contínua de 0 a 39;
- 10 registros `DET_HB` e 10 registros `ATUA_HB`, de 0 a 9;
- timeout nominal exato de 15.000.000 us nas dez repetições;
- zero tempos locais negativos;
- zero perdas de deadline local e fim a fim;
- zero descartes de trace;
- ocupação máxima da fila de trace igual a um item.

## Latências observadas

| Evento | Repetições | Média | P95 | P99 | Máxima | Deadline |
|---|---:|---:|---:|---:|---:|---:|
| Detecção do timeout | 10 | 4.113,4 us | 4.413 us | 4.413 us | 4.413 us | 50.000 us |
| Atuação segura | 10 | 4.145,2 us | 4.442 us | 4.442 us | 4.442 us | 50.000 us |

A atuação mais lenta ocorreu 4,442 ms após o vencimento, usando 8,884% do
prazo disponível. A diferença de aproximadamente 29 us entre as piores
latências de detecção e atuação mostra que o custo adicional da notificação e
da atuação simulada foi pequeno diante do período de verificação do watchdog.

## Interpretação

O resultado demonstra que comandos e telemetria não renovam implicitamente o
watchdog. Somente os 40 heartbeats registrados deslocaram o vencimento. Após
15 s sem renovação, a tarefa watchdog detectou a falha e a tarefa de atuação
levou o sistema ao estado seguro dentro do deadline.

## Limitação

A atuação foi simulada. O ensaio não inclui a escrita física dos canais PWM
nem caracteriza o tempo térmico da planta.

## Arquivos

- trace: `../traces/e7/E7_TRACE.csv`;
- métricas: `e7/E7_METRICAS.csv`.
