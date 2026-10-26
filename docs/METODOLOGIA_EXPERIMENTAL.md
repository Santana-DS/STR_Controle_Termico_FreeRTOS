# Metodologia experimental

## Estratégia de avaliação

A campanha separou a validação funcional do controlador da avaliação temporal
da implementação FreeRTOS. Os ensaios com atuadores desabilitados verificaram
concorrência, escalonamento e segurança sem risco térmico. Os ensaios
energizados avaliaram o comportamento integrado da planta, do controlador e
da infraestrutura de tempo real.

## Grandezas temporais

Para cada job foram registrados os instantes de liberação, início, término e,
quando aplicável, escrita do PWM. A partir deles foram calculados:

- jitter de início: `J = start - release`;
- tempo de execução observado: `C = finish - start`;
- tempo de resposta: `R = finish - release`;
- resposta fim a fim: da liberação da aquisição à atuação correspondente;
- bloqueio no mutex do ADC e ocupação das filas de telemetria.

Os resultados apresentam média, desvio padrão, percentis e máximo observado.
O maior tempo medido é identificado como `Cmax_obs`; ele fundamenta o
orçamento experimental, mas não constitui prova estática de WCET.

## Grandezas funcionais

Nos ensaios energizados foram observados referência, temperaturas `Tp` e
`Ta`, comandos do aquecedor e do cooler, modo do controlador, saturação,
continuidade nas trocas de modo e estado seguro ao término. A comparação com o
PRJ2 empregou RMSE, erro absoluto médio e diferenças nos sinais funcionais.

## Matriz de ensaios

| ID | Condição | Aspecto avaliado |
|---|---|---|
| E0 | replay e execução do núcleo na ESP32 | equivalência numérica do controlador |
| E1 | entradas e saídas simuladas | tarefas, precedências, jitter e deadlines |
| E2 | 12 V desligados | latência de `STOP` e interrupção física |
| E3a | planta conectada, 12 V desligados | ADC, mutex e garantia de PWM nulo |
| E3 | planta energizada por 1 h | integração funcional e temporal nominal |
| E4 | planta energizada, telemetria suspensa | desacoplamento entre caminho crítico e comunicação |
| E5 | carga de fundo progressiva | robustez temporal com prioridade correta |
| E5b | carga nas prioridades 1 e 5 | sensibilidade ao escalonamento inadequado |
| E6 | alternância do cooler | transição entre controladores e continuidade da atuação |
| E7 | interrupção de heartbeat | detecção e atuação segura pelo watchdog |
| E8 | cinco classes de falha | cobertura dos caminhos para o estado seguro |
| E9 | microbenchmarks | custo da própria instrumentação |
| E10 | mutex e semáforo binário | inversão e herança de prioridade |

## Carga computacional

`T_Carga` foi executada no mesmo núcleo das tarefas críticas, com período de
20 ms e demandas nominais de 0%, 10%, 25%, 40% e 60%. No E5 a tarefa usou a
prioridade arquitetural 1. No E5b, a mesma quantidade calibrada de trabalho
foi repetida nas prioridades 1 e 5, isolando o efeito da prioridade sobre os
tempos de resposta.

## Critérios gerais

Um ensaio foi aceito quando apresentou sequências coerentes, timestamps não
negativos, ausência de descartes não previstos, deadlines atendidas e estado
final seguro. Congestionamento deliberado e perdas locais provocadas foram
aceitos somente nos cenários em que constituíam a variável investigada.

Sobretemperatura, sensor inválido, perda de heartbeat, emergência manual ou
falha das filas críticas conduziram imediatamente ao estado seguro, definido
por `PWM_heat = PWM_cool = 0`.
