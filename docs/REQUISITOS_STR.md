# Requisitos do sistema de tempo real

## 1. Objetivo técnico

Executar no ESP32 o controle térmico validado no PRJ2 sob uma arquitetura
FreeRTOS observável e previsível, preservando a lógica funcional e permitindo
relacionar propriedades temporais do software ao desempenho da planta.

Esta especificação registra os requisitos consolidados e confrontados com a
implementação e a campanha experimental final.

## 2. Requisitos funcionais

| ID | Requisito |
|---|---|
| RF-01 | Adquirir `Tp` e `Ta` e entregar ao controle uma amostra coerente e identificada. |
| RF-02 | Executar o algoritmo híbrido do PRJ2 com período nominal de 5,715 s. |
| RF-03 | Gerar referência e comando do cooler conforme o experimento validado. |
| RF-04 | Preservar modelos, ganhos, observadores, anti-windup, histerese e transferência bumpless da baseline. |
| RF-05 | Aplicar os comandos dos atuadores por um único componente de software. |
| RF-06 | Desligar aquecedor e cooler diante de emergência, falha de sensor, sobretemperatura ou perda de comunicação. |
| RF-07 | Receber `START`, `STOP` e `HEARTBEAT` sem bloquear o caminho crítico do controle. |
| RF-08 | Registrar variáveis térmicas, comandos, modo e métricas temporais. |
| RF-09 | Manter operação segura se a fila de telemetria ficar cheia ou o computador parar de consumir dados. |
| RF-10 | Permitir carga computacional controlada somente nos cenários de teste. |

## 3. Requisitos temporais consolidados

Os tempos de computação são tratados separadamente em
[`ANALISE_WCET_WCRT.md`](ANALISE_WCET_WCRT.md). Os valores adotados são
limites experimentais baseados em medições, não WCET estático comprovado.

| ID | Transação ou evento | Requisito inicial |
|---|---|---|
| RT-01 | aquisição periódica | período de 5,715 s e deadline local de 600 ms |
| RT-02 | aquisição até aplicação do PWM | deadline fim a fim de 5,715 s |
| RT-03 | supervisão periódica | período e deadline de 500 ms |
| RT-04 | botão de emergência até PWM zero | deadline de 50 ms |
| RT-05 | comando `STOP` até PWM zero | deadline de 100 ms |
| RT-06 | telemetria de uma amostra | deadline suave de 5,715 s |
| RT-07 | heartbeat ausente | desligamento após 15 s, sem renovação implícita |
| RT-08 | vencimento do heartbeat até atuação segura | deadline de 20 ms |

O deadline fim a fim começa na liberação da aquisição e termina quando o
comando correspondente é efetivamente escrito nos dois canais PWM.

## 4. Requisitos de concorrência

| ID | Requisito |
|---|---|
| RC-01 | Somente a tarefa de atuação pode chamar a escrita dos PWMs durante a operação normal. |
| RC-02 | O estado dos controladores e observadores pertence exclusivamente à tarefa de controle. |
| RC-03 | A amostra é transferida por valor; o controle não lê variáveis parcialmente atualizadas. |
| RC-04 | O ADC é protegido por mutex com herança de prioridade. |
| RC-05 | Telemetria usa fila não bloqueante; descarte é contabilizado, nunca aguardado pelo controle. |
| RC-06 | A emergência é latched: somente reinicialização explícita e condição segura podem liberá-la. |
| RC-07 | A ISR não executa controle, serial, ponto flutuante ou acesso demorado a periféricos. |

## 5. Requisitos de instrumentação

Para cada job relevante devem ser registráveis:

- identificador da tarefa e sequência;
- instante esperado de liberação;
- início e término efetivos;
- tempo de execução observado;
- jitter de liberação ou início;
- tempo de resposta;
- deadline e indicador de perda;
- ocupação máxima e descartes das filas;
- evento de bloqueio ou ativação de segurança.

O relógio de instrumentação é `esp_timer_get_time()`, em microssegundos e com
armazenamento de 64 bits. O custo da própria instrumentação foi medido
separadamente no E9.

## 6. Critérios de aceitação

1. equivalência funcional do núcleo de controle antes do ensaio físico;
2. nenhuma escrita concorrente nos atuadores;
3. nenhuma perda de deadline no cenário nominal;
4. emergência e `STOP` dentro dos respectivos deadlines;
5. congestionamento serial sem bloquear aquisição, controle ou atuação;
6. perdas de telemetria explicitamente contadas;
7. logs suficientes para reproduzir todas as métricas publicadas;
8. explicação quantitativa de qualquer degradação térmica observada.
