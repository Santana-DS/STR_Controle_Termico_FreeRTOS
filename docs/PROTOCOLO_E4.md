# Protocolo E4 — congestionamento da telemetria

## Objetivo

Demonstrar que a tarefa de telemetria e suas filas não bloqueiam aquisição,
controle ou atuação quando a transmissão de registros deixa de acompanhar os
produtores. O descarte de telemetria é esperado, explícito e não pode causar
perda de deadline nem interromper o controle.

## Cenário

- duração fixa: 600 s;
- 0–120 s: telemetria normal;
- 120–420 s: consumo das filas de dados, traces e mensagens suspenso;
- 420–600 s: telemetria retomada e filas drenadas;
- controlador e cenário térmico idênticos à baseline E3;
- heartbeat e comunicação permanecem ativos no núcleo 0;
- aquisição, controle, atuação e supervisão permanecem no núcleo crítico 1.

Durante os cinco minutos de suspensão, os produtores continuam usando envio
não bloqueante. As filas de trace (128 itens) e dados (16 itens) devem atingir
a capacidade máxima; registros posteriores são descartados e contabilizados.

Como parte dos traces será deliberadamente perdida, o firmware mantém também
um resumo temporal independente da fila. O comando `SUMMARY` retorna contagem
de jobs, máximos temporais, perdas de deadline, descartes e ocupações máximas.

## Procedimento

O ensaio foi iniciado com a planta supervisionada. Entre 120 s e 420 s, o
consumo das filas de telemetria foi suspenso pelo próprio firmware, sem
interromper os heartbeats ou as tarefas críticas. Após 420 s, o consumo foi
retomado e as filas remanescentes foram drenadas.

## Critérios de aprovação

- 105 jobs concluídos por aquisição, controle e atuação;
- nenhuma perda de deadline no resumo independente;
- máximos locais e fim a fim dentro dos respectivos deadlines;
- filas de trace e dados alcançando 128 e 16 itens;
- descartes de trace e dados estritamente positivos e contabilizados;
- nenhuma perda de amostra crítica, comando, evento ou mensagem;
- lacuna do CSV coerente com o total de dados descartados;
- todos os heartbeats confirmados;
- temperatura abaixo de 60 °C e encerramento normal em estado seguro.

## Resultado observado

O ensaio físico `E4` apresentou 105 transações
críticas completas, filas saturadas, 37 dados e 707 traces descartados de
forma explícita, zero perda de deadline, 150 heartbeats confirmados e
encerramento normal.
