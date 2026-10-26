# Controlador térmico de referência

O núcleo funcional deriva do firmware final do projeto
[CDig_PRJ_Grupo10](https://github.com/Santana-DS/CDig_PRJ_Grupo10), localizado
em `PRJ2/firmware/final/src/main.cpp`. A implementação original também está
disponível em `firmware/baseline` para comparação direta.

## Estrutura do controle

O controlador opera com período de amostragem de 5,715 s e combina:

- modelo P2DZ para a condição nominal e modelo P1D para a condição com cooler;
- controladores discretos com integração e observadores associados;
- modelo interno da perturbação senoidal;
- saturação e anti-windup por *back-calculation*;
- seleção do controlador a partir do comando do cooler, com histerese e
  confirmação por duas amostras;
- transferência *bumpless* entre os modos;
- ponderação da referência durante a janela senoidal.

## Integração ao sistema de tempo real

O algoritmo de controle foi extraído para `firmware/str/lib/control_core` sem
alteração das equações. Aquisição, cálculo e escrita dos atuadores foram
distribuídos entre tarefas distintas e conectados por filas. O ensaio E0
comparou 634 amostras e os 12 sinais internos do núcleo C++ com o oráculo do
PRJ2, estabelecendo a equivalência numérica antes dos ensaios físicos.

No sistema integrado, a coerência entre referência, amostra, modo e comando é
preservada por mensagens copiadas por valor e números de sequência. A tarefa
de atuação é a única proprietária dos canais PWM.
