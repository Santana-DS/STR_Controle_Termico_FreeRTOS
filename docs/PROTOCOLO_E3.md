# Protocolo serial E3

Baud rate: 115200 bit/s, terminador LF.

## Sequência segura

1. `ARM` limpa o latch de segurança com o sistema parado.
2. `ARM_HB` arma o watchdog de comunicação.
3. `HEARTBEAT` inicia e renova o prazo de 15 s.
4. `START,N` inicia um ensaio de 30 a 3.600 s; `START` usa 3.600 s.
5. Durante o ensaio, enviar `HEARTBEAT` a cada 4 s.

`STOP` percorre comunicação, supervisão e atuação. `STATUS` não renova o
heartbeat.

## Dados funcionais

```text
DATA,seq,t_s,R,Tp,Ta,W,modo,beta,U_nom,U_cool,U_livre,Us,e_sin_nom,e_sin_cool,inov_nom,inov_cool,release_us,acq_finish_us,control_finish_us,actuate_us
```

## Trace

```text
TRACE,task,seq,release_us,start_us,finish_us,deadline_us,jitter_us,exec_us,response_us,miss,e2e_us,e2e_deadline_us,e2e_miss,block_us,q_trace,drops
```

## Encerramento

Após escrever os dois PWM em zero, a telemetria emite
`EVENT,END,<motivo>`. Os motivos incluem `FIM_NORMAL`, `PARADA_MANUAL`,
`HEARTBEAT`, `EMERGENCIA`, `SENSOR_INVALIDO`, `SOBRETEMPERATURA`,
`FALHA_ADC`, `DEADLINE`, `FILA_AMOSTRA` e `FILA_COMANDO`.

Antes do encerramento por sobretemperatura, a origem e a leitura que causou o
disparo são registradas em uma linha adicional:

```text
EVENT,ALARM,SOBRETEMPERATURA,<AQUISICAO|SUPERVISAO>,Tp_C
```

A supervisão calcula sua leitura rápida com 64 conversões. O limite permanece
em 60 °C e uma única leitura filtrada igual ou superior ao limite mantém o
corte imediato. A aquisição principal continua usando 128 conversões.

## Resultado observado

O ensaio energizado de 3.600 s produziu 630 transações e confirmou 899
heartbeats. A resposta fim a fim máxima foi 382,760 ms, sem perda de deadline
ou descarte de trace. A temperatura máxima foi 58,523 °C e o encerramento
normal deixou os dois PWM em zero.
