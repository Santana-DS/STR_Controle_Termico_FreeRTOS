# E0 — equivalência do núcleo de controle

## Objetivo

Reexecutar a lógica do firmware final do PRJ2 usando as temperaturas e os
instantes armazenados no ensaio refinado, sem ADC, PWM, Serial ou FreeRTOS.

## Entrada

- 634 amostras reais;
- dois segmentos de aquisição, reinicializados separadamente;
- temperatura registrada com quatro casas decimais;
- tempo registrado com resolução de milissegundos.

## Resultado

- referência, cooler, modo e beta: coincidência exata;
- comandos livres: erro absoluto máximo inferior a 0,57 PWM16;
- comando saturado registrado: diferença máxima de uma contagem PWM16;
- inovações dos observadores: erro máximo inferior a `1,5e-4` °C;
- todos os sinais dentro das tolerâncias de regressão.

As pequenas diferenças são compatíveis com a quantização textual do CSV: o
firmware calculou com leituras internas de maior precisão e somente depois
formatou os valores para transmissão.

O arquivo `e0_equivalencia_baseline.csv` contém erro máximo, RMSE, erro médio,
tolerância e estado de aprovação para cada sinal.

O resultado estabelece a equivalência numérica entre o núcleo usado pela
arquitetura FreeRTOS e o controlador original nas entradas registradas.
