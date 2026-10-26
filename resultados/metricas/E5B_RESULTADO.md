# E5b — sensibilidade à prioridade

## Resultado

O ensaio desenergizado `E5b` terminou normalmente após
1.200 s. A mesma carga calibrada foi executada primeiro com prioridade 1,
abaixo das tarefas críticas, e depois com prioridade 5, acima da aquisição.
Cada configuração percorreu patamares nominais de 0%, 10%, 25%, 40% e 60%.

Foram concluídas 210 transações funcionais, 21 em cada fase, e confirmados 300
de 300 heartbeats. Não houve descarte, perda de deadline fim a fim ou perda
local de controle, atuação ou supervisão.

| Indicador | Prioridade 1 | Prioridade 5 |
|---|---:|---:|
| transações funcionais | 105 | 105 |
| perdas locais da aquisição | 0 | 3 |
| resposta máxima da aquisição | 388.158 us | 630.274 us |
| resposta fim a fim máxima | 389.052 us | 630.825 us |
| maior resposta do controle | 649 us | 456 us |
| maior resposta da atuação | 245 us | 132 us |
| maior resposta da supervisão | 385.531 us | 386.376 us |

## Comparação por carga

| Carga | Aquisição máxima, prioridade 1 | Perdas, prioridade 1 | Aquisição máxima, prioridade 5 | Perdas, prioridade 5 |
|---:|---:|---:|---:|---:|
| 0% | 388.158 us | 0 | 388.359 us | 0 |
| 10% | 387.893 us | 0 | 410.952 us | 0 |
| 25% | 387.904 us | 0 | 464.518 us | 0 |
| 40% | 387.887 us | 0 | 588.571 us | 0 |
| 60% | 387.893 us | 0 | 630.274 us | 3 |

O trabalho médio por ciclo foi exatamente o mesmo nas duas prioridades para
cada patamar. Portanto, a diferença observada decorre da ordem de
escalonamento, não de uma redução artificial da carga quando ela sofre
preempção.

## Interpretação

Com prioridade 1, a tarefa de carga cedeu o processador à aquisição e a
resposta máxima permaneceu praticamente constante até 60%. Com prioridade 5,
o tempo de resposta da aquisição cresceu com a carga e ultrapassou sua deadline
local de 600 ms três vezes no patamar de 60%. Controle e atuação continuaram
rápidos depois que cada amostra foi produzida, e a deadline fim a fim de
5.715 ms permaneceu atendida.

Esse contraste demonstra que a utilização de CPU, isoladamente, não determina
a escalonabilidade: uma tarefa computacional com prioridade inadequada pode
atrasar uma tarefa crítica mesmo quando o mesmo volume de trabalho é seguro em
prioridade inferior.

## Trace terminal

O arquivo de trace contém aquisições 0 a 210, enquanto dados, controle e
atuação contêm corretamente 0 a 209. A aquisição 210 começou na fronteira de
encerramento e terminou depois que o supervisor encerrou o ensaio; por isso,
seu trace foi preservado, mas a amostra não foi encaminhada. Essa observação
terminal não integra as 210 transações nem representa perda de sequência.
