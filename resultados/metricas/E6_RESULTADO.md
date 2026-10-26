# E6 — transições nominal/cooler

## Resultado

O ensaio `E6` terminou normalmente após 1.500 s. Foram
registradas 263 transações funcionais contínuas e 375 heartbeats, todos
confirmados. As quatro mudanças previstas ocorreram na ordem correta: duas
entradas e duas saídas do modo cooler, sempre confirmadas uma amostra após a
mudança do comando `W`.

| Indicador | Resultado | Critério |
|---|---:|---:|
| trocas de modo | 4 | 4 |
| atraso de confirmação | 1 amostra | 1 amostra |
| maior salto de `U` na troca | 397,22 PWM16 | observar continuidade |
| maior desalinhamento entre candidatos | 820,41 PWM16 | instrumentado |
| resposta fim a fim máxima | 378.384 us | 5.715.000 us |
| aquisição máxima | 377.511 us | 600.000 us |
| controle máximo | 515 us | 100.000 us |
| atuação máxima | 89 us | 20.000 us |
| supervisão máxima | 375.058 us | 500.000 us |
| perdas de deadline | 0 | 0 |
| descartes de trace | 0 | 0 |
| temperatura máxima | 53,167 °C | menor que 60 °C |

## Interpretação

O maior salto de atuação durante uma troca equivale a aproximadamente 0,61%
da escala PWM de 16 bits. O resultado confirma que o alinhamento do estado do
controlador inativo evitou descontinuidades relevantes na variável
manipulada, inclusive nas transições do modo cooler para o nominal.

A temperatura respondeu de forma repetível aos dois acionamentos do cooler e
às duas remoções da perturbação. Os picos observados após desligar o cooler são
respostas físicas do processo e não saltos causados pela seleção do
controlador. A arquitetura manteve precedência, deadlines, heartbeat e
desligamento seguro durante todo o experimento.

O E6 valida a transferência entre modos e passa a integrar a base experimental
do projeto. Não foi realizada ressintonia dos controladores.
