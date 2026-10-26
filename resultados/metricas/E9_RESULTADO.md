# E9 — custo da instrumentação

## Resultado

O microbenchmark `E9` terminou normalmente a 240 MHz.
Foram medidos oito mecanismos em 300 lotes cada, com o benchmark fixado no
núcleo 1 e prioridade 4. Os atuadores permaneceram em nível baixo.

| Operação | Média | P95 | P99 | Máximo |
|---|---:|---:|---:|---:|
| baseline inteira | 0,214 us | 0,215 us | 0,215 us | 0,215 us |
| par de timestamps | 1,212 us | 1,219 us | 1,219 us | 1,219 us |
| construção do trace | 0,378 us | 0,378 us | 0,378 us | 0,378 us |
| envio e retirada da fila | 3,903 us | 3,950 us | 4,000 us | 4,010 us |
| tentativa com fila cheia | 1,671 us | 1,675 us | 1,675 us | 1,675 us |
| contador em seção crítica | 1,088 us | 1,094 us | 1,097 us | 1,097 us |
| formatação textual | 50,634 us | 50,650 us | 51,000 us | 51,050 us |
| pipeline binário combinado | 5,589 us | 5,660 us | 5,660 us | 5,670 us |

## Interpretação

O pipeline combinado representa aproximadamente 0,00095% da deadline de
600 ms da aquisição e 0,0057% da deadline local de 100 ms do controle. Em
relação à execução máxima observada do controle no E5, cerca de 512 us, o
custo médio corresponde a aproximadamente 1,09%.

A formatação textual foi aproximadamente nove vezes mais cara que o pipeline
binário combinado. Esse resultado sustenta a decisão de publicar estruturas
por fila no núcleo crítico e realizar `snprintf` e transmissão serial em
`T_Telemetria`, no núcleo 0.

A tentativa não bloqueante com fila cheia custou no máximo 1,675 us. Em
conjunto com o E4, isso mostra que o congestionamento produz descarte rápido e
contabilizado, sem transformar a telemetria em bloqueio do caminho crítico.

Os valores são custos observados no cenário medido, e não limites formais de
WCET. O uso de lotes reduz a quantização do relógio; interferências raras do
runtime podem exigir margens adicionais em uma análise formal.
