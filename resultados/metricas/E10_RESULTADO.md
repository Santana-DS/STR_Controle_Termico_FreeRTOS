# E10 — inversão e herança de prioridade

## Resultado

O ensaio desenergizado `E10` concluiu 90 repetições:
30 com mutex sem tarefa média, 30 com mutex e tarefa média e 30 com semáforo
binário e tarefa média. O término foi normal e os GPIO dos atuadores
permaneceram em zero.

| Cenário | Espera mediana da tarefa alta | P95 | Máximo | Prioridade efetiva da tarefa baixa |
|---|---:|---:|---:|---:|
| mutex baseline | 16.730 us | 16.730 us | 16.763 us | 6 |
| mutex com herança | 16.730,5 us | 16.731 us | 16.731 us | 6 |
| semáforo binário | 58.404,5 us | 58.405 us | 58.405 us | 2 |

A tarefa média apresentou janela mediana de 41.664 us com mutex e 41.671,5 us
com semáforo. No mutex, a herança elevou temporariamente a tarefa baixa da
prioridade 2 para 6, permitindo que ela liberasse o recurso antes da tarefa
média. Por isso, a espera da tarefa alta permaneceu praticamente idêntica ao
baseline.

No semáforo binário não há herança. A tarefa baixa permaneceu em prioridade 2
e foi preemptada pela tarefa média de prioridade 4. A espera da tarefa alta
cresceu 41.674 us em relação ao mutex, correspondendo diretamente à janela da
tarefa média.

## Observação sobre os tempos de trabalho

Os alvos de calibração eram 20 ms para a tarefa baixa e 50 ms para a tarefa
média. As janelas efetivamente medidas ficaram próximas de 16,67 ms e
41,67 ms, mantendo a proporção de 2,5 e permanecendo praticamente idênticas
entre cenários. A conclusão depende da comparação sob o mesmo trabalho medido,
não da coincidência exata com os valores nominais.

## Visualização

As repetições apresentaram dispersão extremamente pequena: apenas 1 us no
mutex com herança e no semáforo. Por isso, um boxplot convencional colapsava em
linhas. A figura final usa pontos individuais no primeiro painel e mediana,
P95 e máximo no segundo, tornando visível a repetibilidade do experimento.
