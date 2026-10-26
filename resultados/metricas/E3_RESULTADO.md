# E3 — ensaio nominal energizado de uma hora

## Resultado

O ensaio `E3` terminou normalmente após 3.600 s. Foram
registradas 630 transações funcionais contínuas e 899 heartbeats, todos
confirmados. Não houve perda de deadline, descarte de trace, falha de fila,
alarme térmico ou interrupção de comunicação. O estado final confirmou os
dois PWM em zero.

| Indicador | Resultado | Limite |
|---|---:|---:|
| resposta fim a fim máxima | 382.760 us | 5.715.000 us |
| aquisição máxima | 381.899 us | 600.000 us |
| controle máximo | 535 us | 100.000 us |
| atuação máxima | 65 us | 20.000 us |
| supervisão máxima | 378.431 us | 500.000 us |
| bloqueio máximo no ADC | 302.151 us | instrumentado |
| perdas de deadline | 0 | 0 |
| descartes de trace | 0 | 0 |
| temperatura máxima | 58,523 °C | 60 °C |

## Comparação com o PRJ2

A comparação usa somente o segmento 2 do arquivo final do PRJ2, que contém o
ensaio válido de 630 amostras. Referência, modo do controlador e ponderação
`beta` coincidiram em todas as amostras. A diferença máxima no comando do
cooler foi de 6 contagens em 4095, associada à resolução do instante real de
amostragem durante a senoide.

Entre as duas realizações físicas, `Tp` apresentou RMSE de 0,793 °C e erro
absoluto médio de 0,592 °C. A maior temperatura do E3 ocorreu no patamar de
55 °C sob perturbação senoidal. As diferenças restantes são compatíveis com
variação física da planta, da temperatura ambiente e da efetividade do cooler;
o replay E0 já isolou e aprovou a equivalência numérica do núcleo de controle.

O resultado caracteriza a operação nominal da planta sob a arquitetura de
tempo real e fornece a referência para os ensaios de carga e interferência.
