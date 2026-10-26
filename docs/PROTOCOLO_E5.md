# Protocolo E5 — carga progressiva de CPU

## Objetivo

Medir jitter e tempos de resposta do caminho crítico sob demanda computacional
progressiva no mesmo núcleo. Este primeiro E5 usa a prioridade arquitetural
correta para `T_Carga`: prioridade 1, abaixo de aquisição, controle,
supervisão e atuação.

## Segurança e interpretação

O ensaio deve ser executado com os 12 V desligados. A ESP32 lê os sensores e
executa todo o caminho de controle, mas a planta não recebe potência.

Os percentuais são cargas nominais: em cada janela de 20 ms, `T_Carga`
solicita uma janela ocupada proporcional ao patamar. Como a tarefa é
preemptível e tem a menor prioridade, o percentual não deve ser interpretado
como medição direta da utilização total da CPU. Essa distinção orienta a
interpretação dos resultados.

## Cenário

| Intervalo | Carga nominal | Orçamento em 20 ms |
|---:|---:|---:|
| 0–120 s | 0% | 0 ms |
| 120–240 s | 10% | 2 ms |
| 240–360 s | 25% | 5 ms |
| 360–480 s | 40% | 8 ms |
| 480–600 s | 60% | 12 ms |

O firmware preserva resumos independentes para cada fase: jobs críticos,
jitter máximo, respostas locais, resposta fim a fim, perdas de deadline,
ciclos de carga, orçamento acumulado e maior janela observada.

## Procedimento

Com a fonte de 12 V desligada, os cinco patamares foram aplicados
automaticamente em intervalos de 120 s. O coletor manteve o heartbeat e
registrou, por fase, jitter, resposta local, resposta fim a fim e execução da
tarefa de carga.

## Critérios de aprovação

- 105 transações completas e sequenciais;
- aproximadamente 21 jobs de aquisição, controle e atuação por fase;
- cinco eventos de mudança de carga;
- tarefa de carga executada em todos os patamares;
- orçamento acumulado coerente com carga, período e quantidade de ciclos;
- nenhuma perda de deadline ou descarte de fila;
- máximos locais e fim a fim dentro dos respectivos deadlines;
- todos os heartbeats confirmados;
- encerramento normal com os PWM em zero.

## Resultado observado

O ensaio desenergizado `E5` apresentou cinco
fases completas, 105 transações críticas, 150 heartbeats confirmados, zero
perda de deadline e zero descarte.
