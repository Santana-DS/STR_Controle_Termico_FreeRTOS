# Resultado do ensaio E2

## Configuração

- ESP32 DevKit V1 alimentada apenas por USB;
- fonte de 12 V da planta desligada;
- entrada térmica e atuação simuladas, sem ADC e sem PWM;
- 20 repetições do comando serial `STOP`;
- 10 acionamentos do botão `BOOT`/GPIO 0;
- deadline fim a fim de 100 ms para `STOP`;
- deadline de 50 ms para a emergência física.

## Integridade

O ensaio produziu 118 registros. Os eventos de segurança apresentaram:

- 20 registros `SUP_STOP` e 20 registros `ATUA_STOP`;
- 10 registros `ATUA_EMERG`;
- sequências contínuas de 0 a 19 para `STOP` e de 0 a 9 para emergência;
- zero tempos locais negativos;
- zero perdas de deadline local e fim a fim;
- zero descartes de trace;
- ocupação máxima da fila de trace igual a um item.

## Latências observadas

| Evento | Repetições | Média | P95 | P99 | Máxima | Deadline |
|---|---:|---:|---:|---:|---:|---:|
| Atuação por `STOP` | 20 | 40,6 us | 41,45 us | 63,49 us | 69 us | 100.000 us |
| Emergência pelo `BOOT` | 10 | 13,5 us | 15,65 us | 16,73 us | 17 us | 50.000 us |

A pior resposta do `STOP` consumiu 0,069% de seu prazo. A pior emergência
física consumiu 0,034% do prazo correspondente. Esses resultados comprovam o
caminho de software e o caminho direto de interrupção até a atuação segura
simulada.

## Limitação

O E2 comprova os mecanismos de segurança e sua temporização com a planta
desenergizada. Os valores não incluem o custo de escrita nos canais PWM nem
caracterizam o tempo de resposta térmico da planta.

## Arquivos

- trace: `../traces/e2/E2_TRACE.csv`;
- métricas: `e2/E2_METRICAS.csv`.
