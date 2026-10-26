# Resultado do ensaio E1

## Configuração

- ESP32 DevKit V1 alimentada apenas por USB;
- fonte de 12 V da planta desligada;
- FreeRTOS integrado ao framework Arduino ESP32;
- entrada térmica sintética e atuação simulada;
- período de aquisição e controle: 5,715 s;
- período de supervisão: 500 ms;
- duração solicitada: 1.800 s.

## Integridade

O ensaio produziu 4.551 registros ao longo de aproximadamente 1.801,8 s:

- 315 aquisições, 315 controles e 315 atuações;
- 3.604 jobs de supervisão;
- um evento `STOP` na supervisão e um na atuação;
- sequências contínuas e períodos nominais exatos;
- zero tempos negativos;
- zero perdas de deadline local e fim a fim;
- zero descartes de trace;
- ocupação máxima da fila de trace igual a um item.

## Máximos observados

| Caminho | Jitter máximo | Execução máxima | Resposta máxima | Deadline |
|---|---:|---:|---:|---:|
| Aquisição sintética | 430 us | 101 us | 531 us | 600.000 us |
| Controle | 19 us | 501 us | 520 us | 100.000 us |
| Atuação simulada | 31 us | 4 us | 35 us | 20.000 us |
| Supervisão | 0 us | 2 us | 2 us | 500.000 us |

A resposta fim a fim máxima da cadeia normal foi 622 us, diante de um
deadline de 5.715.000 us. O caminho completo do `STOP` respondeu em 57 us,
diante de um deadline de 100.000 us.

O máximo de 501 us do controle ocorreu somente no primeiro job, durante a
inicialização dos estados. Nos demais jobs, o percentil 99 da execução foi
51 us. Não houve degradação mensurável entre o smoke test e o ensaio longo.

## Limitação

O E1 valida a arquitetura, as precedências, as filas e a instrumentação, mas
não mede o custo do ADC nem constitui caracterização de WCET da planta física.
Esses elementos pertencem aos ensaios posteriores.

## Arquivos

- trace: `../traces/e1/E1_TRACE.csv`;
- métricas: `e1/E1_METRICAS.csv`.
