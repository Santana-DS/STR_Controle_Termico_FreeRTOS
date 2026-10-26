# A1 — síntese temporal e de concorrência

## Objetivo

A síntese relaciona os resultados de E3, E5b, E8, E9 e E10 sem introduzir
novas medições.

## Caminho crítico no E3

A sequência 0 do ensaio nominal de uma hora fornece um exemplo completo da
precedência aquisição → controle → atuação.

| Etapa | Início após liberação | Execução | Término após liberação |
|---|---:|---:|---:|
| aquisição | 6 us | 381.899 us | 381.905 us |
| controle | 382.012 us | 535 us | 382.547 us |
| atuação | 382.695 us | 65 us | 382.760 us |

A aquisição representa 99,78% da resposta fim a fim observada nessa
transação. Sua resposta utilizou 63,65% da deadline local de 600 ms. O caminho
completo utilizou 6,70% da deadline fim a fim de 5,715 s. As lacunas de 107 us
entre aquisição e controle e de 148 us entre controle e atuação correspondem
à liberação por fila/notificação e ao despacho das tarefas.

## Síntese das evidências

| Questão | Evidência | Conclusão |
|---|---|---|
| a prioridade protege o caminho crítico? | E5b manteve a aquisição em aproximadamente 388 ms com prioridade 1; com prioridade 5, chegou a 630,274 ms e perdeu três deadlines | a atribuição de prioridades é causal para a escalonabilidade |
| as falhas levam ao estado seguro a tempo? | os 25 eventos do E8 terminaram com PWM zero; o pior caso consumiu 26,05% da deadline | os cinco caminhos possuem margem temporal |
| o trace altera materialmente o sistema? | o pipeline binário custou 5,589 us em média; `snprintf` custou 50,634 us | o registro binário é pequeno e a formatação deve permanecer fora do núcleo crítico |
| o mutex limita a inversão? | a espera mediana foi 16,7305 ms com herança e 58,4045 ms sem herança | a herança eliminou os 41,674 ms de interferência da tarefa média |

## Resultados quantitativos principais

- no E5b, a resposta máxima da aquisição com prioridade 5 cresceu 62,29%
  entre 0% e 60% de carga;
- no patamar de 60%, a resposta excedeu a deadline local em 30.274 us, ou
  5,05%;
- o maior uso de deadline no E8 foi 26,05% para sobretemperatura, seguido por
  8,94% para perda de heartbeat;
- a formatação textual do E9 foi 9,06 vezes mais cara que o pipeline binário;
- o pipeline binário correspondeu a 0,0056% da deadline de controle de
  100 ms;
- no E10, a ausência de herança multiplicou a espera mediana da tarefa alta
  por 3,49.

## Conclusão

O sistema atende as deadlines na configuração projetada e mantém saídas
seguras nas falhas previstas. Os ensaios adversos mostram que esse resultado
depende de decisões explícitas de arquitetura: prioridades corretas,
telemetria fora do caminho crítico, mutex com herança e atuação segura de alta
prioridade. A síntese fornece a base quantitativa para avaliar a arquitetura.
