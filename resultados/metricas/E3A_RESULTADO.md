# Resultado E3a — preflight passivo da planta

Ensaio aprovado em 23/10/2026 na ESP32 DevKit V1 conectada à planta, pela
porta COM3. A fonte de 12 V permaneceu desligada. O firmware configurou os
ADCs e os temporizadores PWM reais, porém manteve aquecedor e ventilador em
zero durante toda a coleta.

## Resultado

| Indicador | Valor |
|---|---:|
| Aquisições | 30 |
| Conversões por sensor em cada aquisição | 128 |
| Período | 1 s |
| Deadline da aquisição | 600.000 us |
| Execução média | 315.375 us |
| Execução máxima | 315.591 us |
| Resposta máxima | 315.628 us |
| Jitter máximo | 37 us |
| Espera máxima pelo mutex do ADC | 7 us |
| Perdas de deadline | 0 |
| Amostras com PWM não nulo | 0 |
| `Tp` média | 25,249 °C |
| `Tp` mínima / máxima | 24,474 / 25,663 °C |
| `Ta` média | 25,542 °C |
| `Ta` mínima / máxima | 25,359 / 25,746 °C |
| Diferença máxima entre sensores | 1,127 °C |

As duas temperaturas permaneceram próximas da ambiente e dentro da faixa
plausível definida no protocolo. A aquisição consumiu aproximadamente 52,6%
da deadline no pior caso. O resultado confirma o mapa físico, a conversão dos
LM35, o mutex do ADC e o estado seguro das saídas antes do ensaio energizado.
