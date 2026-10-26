# Protocolo serial E3a

Baud rate: 115200 bit/s, terminador LF.

## Comandos

| Comando | Resposta principal | Função |
|---|---|---|
| `PING` | `ACK,PONG,E3A_IO_PREFLIGHT` | identifica o firmware |
| `START_IO` | `ACK,START_IO,30` | inicia 30 amostras |
| `START_IO,N` | `ACK,START_IO,N` | inicia entre 1 e 300 amostras |
| `STOP` | `ACK,STOP` | interrompe e força PWM zero |
| `STATUS` | `STATUS,E3A,executando,hardware,pwm_heat,pwm_cool` | consulta estado |

## Registro de amostra

```text
IO,seq,release_us,start_us,finish_us,deadline_us,jitter_us,exec_us,response_us,miss,Tp_C,Ta_C,pwm_heat,pwm_cool,adc_wait_us,sensors_ok,outputs_zero,n_adc
```

O registro contém 128 conversões por sensor. Ao terminar, o firmware envia
`DONE,E3A,OUTPUTS_ZERO,1`. Qualquer violação local de sensor, deadline ou PWM
encerra o ensaio, força as saídas a zero e produz uma linha `ALARM,E3A,...`.
Quando a referência em microssegundos fica poucos microssegundos após o tick
de liberação, o firmware usa o início observado como limite inferior. Assim,
o jitter registra atrasos reais sem criar valores negativos por desalinhamento
entre os relógios do FreeRTOS e do `esp_timer`.

## Critério do coletor

O coletor exige sequência contínua, tempos não negativos, ausência de perda
da deadline de 600 ms, PWM sempre zero, temperaturas entre 5 e 60 °C e
diferença máxima de 20 °C entre os sensores. Os CSVs são gravados antes das
asserções finais para preservar evidência em caso de reprovação.

## Resultado observado

As 30 aquisições foram concluídas sem perda da deadline de 600 ms. A resposta
máxima foi 315,628 ms, a espera máxima pelo mutex do ADC foi 7 us e ambos os
PWM permaneceram em zero. A diferença máxima entre os sensores foi 1,127 °C.
