# Protocolo E10 — inversão e herança de prioridade

## Objetivo

Demonstrar experimentalmente a inversão de prioridade e o efeito da herança
implementada pelo mutex FreeRTOS. O ensaio usa três tarefas no núcleo 1:

| Tarefa | Prioridade | Papel |
|---|---:|---|
| `T_Alta` | 6 | solicita o recurso já ocupado e mede a espera |
| `T_Media` | 4 | executa 50 ms de carga sem usar o recurso |
| `T_Baixa` | 2 | mantém o recurso durante 20 ms de trabalho |

## Cenários

1. `MUTEX_BASELINE`: tarefa média ausente;
2. `MUTEX_HERANCA`: tarefa média presente e recurso protegido por mutex;
3. `BINARIO_INVERSAO`: tarefa média presente e recurso representado por
   semáforo binário, que não possui herança.

Quando `T_Alta` bloqueia no mutex, a prioridade efetiva de `T_Baixa` deve
subir temporariamente de 2 para 6. Assim, `T_Media` não prolonga o bloqueio.
No semáforo binário, `T_Baixa` permanece em prioridade 2 e é preemptada pela
tarefa média, prolongando a espera da tarefa alta.

Cada cenário possui 30 repetições. O trabalho é executado por quantidade fixa
de iterações calibradas no boot.

## Segurança

O E10 não usa ADC ou PWM. Os GPIO 25 e 26 permanecem em zero. A fonte de 12 V
deve ficar desligada.

## Procedimento

Os três cenários foram executados em sequência, com 30 repetições cada. A
tarefa alta registrou o tempo de espera pelo recurso e a prioridade efetiva da
tarefa baixa durante o bloqueio.

## Critérios

- 30 repetições completas por cenário;
- prioridade efetiva 6 nos dois cenários com mutex;
- prioridade efetiva 2 no cenário com semáforo binário;
- mediana do semáforo pelo menos 30 ms maior que a do mutex com herança;
- a tarefa média não aumenta materialmente a mediana quando há herança;
- término normal e saídas em zero.

## Resultado observado

O ensaio `E10` teve 30 repetições por
cenário. As medianas foram 16,730 ms no mutex baseline, 16,731 ms no mutex com
herança e 58,405 ms no semáforo binário.
