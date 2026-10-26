# E5 — carga progressiva de CPU

## Resultado

O ensaio desenergizado `E5` terminou normalmente após
600 s. A tarefa de fundo `T_Carga`, fixada no mesmo núcleo das tarefas
críticas e com prioridade inferior, percorreu cinco fases de 120 s: 0%, 10%,
25%, 40% e 60% de demanda nominal. A fonte de 12 V permaneceu desligada.

Foram concluídas 105 transações de aquisição, controle e atuação, com 150 de
150 heartbeats confirmados. Nenhuma tarefa perdeu deadline e nenhum registro
de dados ou trace foi descartado.

| Indicador | Resultado | Critério |
|---|---:|---:|
| fases completas | 5 | 5 |
| aquisições por fase | 21, 21, 21, 21, 21 | 20 a 22 |
| controles por fase | 21, 21, 21, 21, 21 | 20 a 22 |
| atuações por fase | 21, 21, 21, 21, 21 | 20 a 22 |
| perdas de deadline | 0 | 0 |
| descartes de trace | 0 | 0 |
| heartbeats confirmados | 150 de 150 | todos |
| resposta fim a fim máxima | 381.643 us | 5.715.000 us |
| aquisição máxima | 381.120 us | 600.000 us |
| controle máximo | 512 us | 100.000 us |
| atuação máxima | 69 us | 20.000 us |
| supervisão máxima | 379.041 us | 500.000 us |
| temperatura máxima | 25,023 °C | menor que 60 °C |

## Resultados por fase

| Carga nominal | Jitter máx. aquisição | Resposta máx. aquisição | Resposta máx. supervisão | Fim a fim máx. |
|---:|---:|---:|---:|---:|
| 0% | 53.438 us | 381.294 us | 339.032 us | 381.629 us |
| 10% | 43.444 us | 381.294 us | 354.040 us | 381.628 us |
| 25% | 28.445 us | 381.295 us | 369.035 us | 381.633 us |
| 40% | 73.444 us | 381.325 us | 379.041 us | 381.643 us |
| 60% | 68.438 us | 381.295 us | 329.038 us | 381.633 us |

Os tempos de aquisição e fim a fim permaneceram praticamente constantes. O
jitter não cresceu monotonicamente com a carga, mas continuou pequeno em
relação ao período funcional. A supervisão apresentou variação maior porque
compartilha o ADC com a aquisição; ainda assim, permaneceu abaixo de sua
deadline de 500 ms em todas as fases.

## Interpretação da tarefa de carga

Os percentuais configurados representam **demanda nominal**, calculada pelo
orçamento de execução ocupado a cada período de 20 ms: 0, 2, 5, 8 e 12 ms.
Eles não são uma medição direta da utilização total do processador.

A maior janela de parede observada para uma ativação de `T_Carga` chegou a
390.485 us. Esse valor inclui o tempo em que a tarefa de baixa prioridade
ficou preemptada por tarefas críticas, especialmente durante a leitura do ADC;
portanto, não corresponde a 390 ms de ocupação contínua da CPU. Essa
preempção é justamente o comportamento esperado do escalonamento por
prioridades: mesmo sob demanda nominal de 60%, o trabalho crítico conservou
suas deadlines e precedências.

O E5 valida a robustez temporal da arquitetura até o patamar ensaiado. O
resultado não prova capacidade ilimitada nem substitui uma medição de
utilização efetiva por contador de ciclos; ele demonstra que, neste cenário e
com a prioridade adotada, a carga de fundo não comprometeu o caminho crítico.
