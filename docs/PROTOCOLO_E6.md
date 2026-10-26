# Protocolo E6 — transições nominal/cooler

## Objetivo

Validar, na planta física, as trocas bidirecionais entre os controladores
nominal e com cooler, preservando continuidade de atuação, deadlines e
desligamento seguro. O ensaio não é uma sintonia de controle: ele exercita a
arquitetura de tempo real em uma condição que o E3 nominal não percorreu.

## Cenário

- duração: 1500 s (25 min);
- referência: 45 °C durante todo o ensaio;
- `beta`: 1 durante todo o ensaio;
- período funcional: 5,715 s;
- comando do cooler em patamares de 300 s:
  `0 → 3211 → 0 → 3211 → 0`;
- proteção térmica: saída segura se `Tp >= 60 °C`;
- heartbeat e comando `STOP` idênticos aos do E3.

O modo exige duas amostras consecutivas para confirmar a transição. Assim, o
CSV deve registrar quatro mudanças de comando e quatro mudanças de modo, cada
mudança de modo uma amostra após a respectiva mudança de `W`.

## Procedimento

Com a planta energizada e supervisionada, o firmware alternou o comando do
cooler nos cinco patamares definidos. O coletor manteve o heartbeat, registrou
os dois candidatos de controle e verificou a confirmação do modo uma amostra
após cada mudança de comando.

## Critérios de aprovação

- encerramento `FIM_NORMAL`;
- sequência funcional completa e sem lacunas;
- quatro comandos e quatro trocas de modo na ordem prevista;
- confirmação de cada modo uma amostra após a mudança de comando;
- nenhum deadline perdido e nenhum descarte de trace;
- todos os heartbeats confirmados;
- `Tp` e `Ta` na faixa segura de 5 a 60 °C;
- PWM dentro das faixas previstas;
- estado final seguro.

Além das métricas temporais do E3, o coletor calcula o maior salto da atuação
na troca, o desalinhamento entre os dois candidatos e o atraso de confirmação
em amostras.

## Resultado observado

O ensaio físico `E6` apresentou 263 amostras, quatro
trocas de modo, 375 heartbeats confirmados, zero perdas de deadline, zero
descartes e encerramento normal.
