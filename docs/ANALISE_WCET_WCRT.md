# Análise de WCET e WCRT

## 1. Escopo

Esta análise usa os ensaios aceitos E3, E4, E5, E6 e E8 para caracterizar as
quatro tarefas do núcleo crítico. O E5b não entra na distribuição nominal
porque sua segunda configuração eleva deliberadamente a prioridade da carga.
Seu maior bloqueio do ADC, entretanto, é mantido como evidência conservadora.

Os resultados não constituem uma prova estática de WCET. O ESP32 executa
FreeRTOS, acessa ADCs e possui efeitos de runtime e memória que não foram
modelados no nível de instrução. Por isso, o termo `C_MB-WCET` significa um
limite experimental adotado para análise: maior demanda observada, margem de
5% e arredondamento para cima.

## 2. Grandezas usadas

- `C_obs`: maior demanda observada entre os pontos de instrumentação;
- `C_MB-WCET`: `C_obs` com margem de 5% e arredondamento;
- `O`: custo adicional de liberação e despacho não contido em `C_obs`;
- `Q = C_MB-WCET + O`: orçamento usado como demanda na RTA;
- `B`: bloqueio máximo adotado para recurso compartilhado;
- `R`: tempo de resposta calculado por análise de prioridade fixa.

Para a supervisão, `C_obs` exclui o tempo aguardando o mutex do ADC. Esse
tempo aparece separadamente em `B`. Na aquisição, o timestamp final ocorre
depois da liberação do mutex. Em 656 de 1.080 amostras, o intervalo bruto
contém uma execução da supervisão que aguardava o ADC. Essa demanda sobreposta
foi subtraída pelos intervalos dos traces para não reaparecer na RTA. As
esperas ocupadas das conversões ADC permanecem no orçamento.

O máximo de resposta da atuação foi 241 us, embora sua execução tenha durado
no máximo 93 us. A diferença de 148 us corresponde à entrega da mensagem e
ao despacho. O modelo reserva 160 us em `O`, de modo que o limite analítico
também cubra esse comportamento observado.

## 3. Limites experimentais

| Tarefa | Amostras | Média | P99 | Máximo observado | `C_MB-WCET` | `Q` |
|---|---:|---:|---:|---:|---:|---:|
| atuação | 1.078 | 42,62 us | 61 us | 93 us | 110 us | 270 us |
| supervisão | 12.321 | 76,067 ms | 77,697 ms | 77,976 ms | 82 ms | 82 ms |
| controle | 1.078 | 137,25 us | 217 us | 557 us | 600 us | 600 us |
| aquisição, ajustada | 1.080 | 304,707 ms | 310,911 ms | 311,216 ms | 330 ms | 330 ms |

O coeficiente de variação foi 14,90% na atuação, 3,33% na supervisão, 35,55%
no controle e 0,73% na aquisição ajustada. O CV alto do controle tem pouco
efeito absoluto: mesmo o máximo observado permaneceu abaixo de 0,6 ms. Nas
15 detecções de heartbeat do E7 e E8, o watchdog executou em até 15 us; foi
adotado orçamento de 20 us.

## 4. Modelo de resposta

No núcleo 1 usa-se escalonamento preemptivo por prioridade fixa. Para cada
tarefa `i`, a iteração aplicada foi:

```text
R_i^(k+1) = Q_i + B_i + soma_j(ceil(R_i^k/T_j) * Q_j)
```

O somatório contém tarefas de prioridade superior. No cenário nominal,
controle e atuação têm separação mínima de 5,715 s porque são sucessoras da
aquisição. A supervisão tem período de 500 ms e o watchdog, 5 ms. A hipótese
independente para as sucessoras é conservadora: ela permite uma interferência
de cada uma mesmo quando a precedência da transação impediria certas
sobreposições.

O WCRT de uma ativação do watchdog é 290 us. Como a expiração do heartbeat
pode ocorrer logo após uma verificação, o limite contado desde o vencimento
inclui ainda uma fase de varredura de 5 ms, totalizando 5,290 ms.

O bloqueio da supervisão foi definido em 325 ms. O valor cobre o máximo de
308,864 ms medido no E5b, acrescido de aproximadamente 5% e arredondado. Os
eventos de falha não fazem parte desta recorrência nominal; suas latências
foram medidas diretamente no E8.

## 5. Resultados da WCRT

| Tarefa | `Q` | `B` | `R_WCRT` | Deadline | Uso da deadline | Máximo observado |
|---|---:|---:|---:|---:|---:|---:|
| atuação | 0,270 ms | 0 | 0,270 ms | 20 ms | 1,35% | 0,241 ms |
| watchdog, desde o vencimento | 0,020 ms | 0 | 5,290 ms | 20 ms | 26,45% | 4,439 ms |
| supervisão | 82 ms | 325 ms | 408,910 ms | 500 ms | 81,78% | 385,579 ms |
| controle | 0,600 ms | 0 | 83,210 ms | 100 ms | 83,21% | 75,552 ms |
| aquisição | 330 ms | 0 | 414,530 ms | 600 ms | 69,09% | 388,950 ms |

Todas as recorrências convergiram em até três iterações. O limite conservador
da cadeia aquisição-controle-atuação, obtido pela soma dos três WCRT locais,
foi 498,010 ms. Isso representa 8,71% da deadline fim a fim de 5,715 s. O
maior valor fim a fim observado nos ensaios nominais foi 389,826 ms.

A utilização baseada nos orçamentos `Q` e períodos nominais foi 22,590% no
núcleo crítico. Esse valor é uma verificação de plausibilidade, não substitui
a análise de resposta, pois não representa bloqueio nem deadlines distintas.

## 6. Interpretação e limites

O maior risco temporal não está no algoritmo de controle. Ele aparece na
aquisição e no compartilhamento do ADC. O controle usa menos de 1 ms de CPU,
mas pode aguardar uma execução da supervisão e, por isso, seu WCRT chega a
83,210 ms após incluir também o watchdog. A supervisão, por sua vez, recebe
um termo de bloqueio de 325 ms.

Os limites analíticos excederam os máximos observados em todas as tarefas. A
menor diferença foi 29 us na atuação e a maior, 25,580 ms na aquisição. A
análise permanece condicionada às
seguintes hipóteses:

- firmware, frequências e configuração FreeRTOS iguais às dos ensaios;
- apenas a carga nominal no núcleo crítico;
- separação mínima de 5,715 s para controle e atuação normais;
- uma única instância de cada tarefa por vez;
- bloqueio do ADC limitado pelo maior valor experimental adotado;
- ausência de uma prova estática no nível de instruções.

Os CSVs reproduzíveis estão em `resultados/metricas/a2`. As figuras vetoriais
estão em `resultados/figuras/impressao`.
