# Protocolo E5b — sensibilidade à prioridade

## Objetivo

Comparar a resposta temporal do mesmo caminho físico e da mesma quantidade
calibrada de trabalho computacional quando `T_Carga` recebe:

- prioridade 1, abaixo de todas as tarefas críticas;
- prioridade 5, deliberadamente inadequada, acima da aquisição e no mesmo
  nível do controle.

O E5b é um experimento de contraste. A prioridade 5 nunca é proposta como
configuração de produção.

## Segurança

A fonte de 12 V deve permanecer desligada. O firmware lê os dois sensores e
executa o controlador, mas força fisicamente os dois PWM a zero. Os valores de
controle no CSV são comandos **calculados**, não comandos aplicados.

Falha de sensor, ADC, supervisão, atuação, heartbeat ou deadline fim a fim
encerra o ensaio. A perda da deadline local de aquisição é registrada e o
ensaio continua, pois essa é uma variável deliberadamente investigada com as
saídas anuladas.

## Carga calibrada

Durante a inicialização, o firmware mede quantas iterações do núcleo inteiro
de carga são executadas por microssegundo. Cada ativação posterior executa uma
quantidade fixa de iterações. Assim, uma preempção aumenta o tempo de parede,
mas não elimina o trabalho restante, corrigindo a limitação metodológica do
E5 original.

Se uma ativação ultrapassar seu período, liberações antigas são descartadas e
a agenda é retomada a partir do instante atual. Não há execução em rajada para
recuperar jobs de carga obsoletos. O contador `ciclos_acima_periodo` torna
esses casos observáveis.

O núcleo executado durante o ensaio é exatamente o mesmo laço aritmético usado
na calibração. Consultas ao estado do FreeRTOS são feitas fora desse laço, para
que não exista custo sistemático ausente da calibração.

## Cenário

Cada fase dura 120 s e `T_Carga` tem período de 20 ms.

| Intervalo | Prioridade | Demanda nominal |
|---:|---:|---:|
| 0–120 s | 1 | 0% |
| 120–240 s | 1 | 10% |
| 240–360 s | 1 | 25% |
| 360–480 s | 1 | 40% |
| 480–600 s | 1 | 60% |
| 600–720 s | 5 | 0% |
| 720–840 s | 5 | 10% |
| 840–960 s | 5 | 25% |
| 960–1080 s | 5 | 40% |
| 1080–1200 s | 5 | 60% |

## Procedimento

Os cinco patamares de carga foram executados primeiro na prioridade 1 e depois
na prioridade 5, mantendo a fonte de 12 V desligada e a mesma quantidade
calibrada de trabalho por ativação.

## Critérios de integridade

- 210 transações funcionais completas e sequenciais;
- aproximadamente 21 transações por fase;
- trabalho médio por ciclo idêntico nas prioridades 1 e 5 para cada carga;
- nenhuma perda na configuração correta;
- nenhuma perda de deadline de controle, atuação, supervisão ou fim a fim;
- perdas locais da aquisição na prioridade 5 permitidas e contabilizadas;
- zero descarte interno, heartbeats íntegros e término normal;
- PWM físicos invariavelmente em zero.

A aquisição pode registrar um único trace terminal com sequência 210 quando
um job iniciado antes dos 1.200 s termina simultaneamente ao encerramento pelo
supervisor. Esse job não é encaminhado ao controle e não integra as 210
transações funcionais; sua presença preserva a observabilidade do trabalho já
iniciado e não caracteriza perda de sequência.

O aumento de resposta sob prioridade 5 é uma variável de resultado, não
uma condição artificial de aprovação do coletor.

## Resultado observado

O ensaio desenergizado `E5b` apresentou 210
transações e 300 heartbeats. A prioridade 1 preservou todas as deadlines; a
prioridade 5 produziu três perdas locais da aquisição no patamar de 60%, sem
perda fim a fim, descarte ou estado final inseguro.
