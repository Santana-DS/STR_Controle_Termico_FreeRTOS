# E4 — congestionamento da telemetria

## Resultado

O ensaio `E4` terminou normalmente após 600 s. A
telemetria operou normalmente por 120 s, permaneceu suspensa por 300 s e foi
retomada aos 420 s. Os marcos medidos foram 120,003 s e 420,003 s.

Durante a suspensão, as filas atingiram suas capacidades máximas e passaram a
descartar apenas registros de observação. O resumo independente das filas
confirmou que o caminho crítico continuou completo.

| Indicador | Resultado | Critério |
|---|---:|---:|
| jobs de aquisição | 105 | 105 |
| jobs de controle | 105 | 105 |
| jobs de atuação | 105 | 105 |
| jobs de supervisão | 1.200 | instrumentado |
| dados recebidos | 68 de 105 | perda esperada |
| dados descartados | 37 | maior que zero e contabilizado |
| traces descartados | 707 | maior que zero e contabilizado |
| pico da fila de dados | 16 | capacidade 16 |
| pico da fila de trace | 128 | capacidade 128 |
| mensagens descartadas | 0 | 0 |
| resposta fim a fim máxima | 389.826 us | 5.715.000 us |
| aquisição máxima | 388.944 us | 600.000 us |
| controle máximo | 530 us | 100.000 us |
| atuação máxima | 93 us | 20.000 us |
| supervisão máxima | 385.579 us | 500.000 us |
| perdas de deadline | 0 | 0 |
| heartbeats confirmados | 150 de 150 | todos |
| temperatura máxima recebida | 55,589 °C | menor que 60 °C |

## Evidência de desacoplamento

O CSV funcional contém uma única lacuna: após a sequência 36, em 205,740 s,
a próxima amostra transmitida foi a sequência 74, em 422,910 s. As 37
sequências ausentes coincidem exatamente com o contador de descartes de dados.

Apesar dessa perda deliberada de observabilidade, o resumo interno registrou
105 aquisições, 105 controles e 105 atuações. Isso demonstra que o enchimento
das filas não bloqueou nem eliminou transações críticas. A referência mudou de
45 °C para 55 °C aproximadamente aos 400 s, ainda durante o congestionamento;
quando a telemetria voltou, a temperatura já estava em 53,028 °C e convergiu
para o novo patamar.

O ensaio valida a fila não bloqueante prevista em RC-05 e os critérios de
aceitação relativos ao congestionamento serial e à contabilização explícita
das perdas de telemetria.
