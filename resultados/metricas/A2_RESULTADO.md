# A2 — WCET experimental e WCRT

## Resultado

A A2 consolidou 15.557 registros das quatro tarefas críticas nos ensaios E3,
E4, E5, E6 e E8. O maior valor medido foi usado para construir um limite
experimental com margem de 5% e arredondamento. A análise não reivindica WCET
estático.

| Tarefa | `C_obs` | Orçamento RTA | Bloqueio | WCRT | Deadline |
|---|---:|---:|---:|---:|---:|
| atuação | 93 us | 270 us | 0 | 270 us | 20 ms |
| watchdog | 15 us | 20 us | 0 | 5,290 ms desde o vencimento | 20 ms |
| supervisão | 77,976 ms | 82 ms | 325 ms | 408,910 ms | 500 ms |
| controle | 557 us | 600 us | 0 | 83,210 ms | 100 ms |
| aquisição, ajustada | 311,216 ms | 330 ms | 0 | 414,530 ms | 600 ms |

O orçamento da atuação inclui 160 us para entrega e despacho. O bloqueio da
supervisão cobre o máximo de 308,864 ms observado no E5b com margem. Na
aquisição, a demanda da supervisão contida após a liberação do mutex foi
subtraída para evitar dupla contagem; as esperas ocupadas do ADC permaneceram.
O limite do watchdog soma 5 ms de fase de varredura ao WCRT de tarefa de
290 us.

Todas as recorrências convergiram em até três iterações. O maior uso de
deadline foi 83,21% no controle. A soma conservadora dos WCRT da aquisição,
controle e atuação foi 498,010 ms, equivalente a 8,71% da deadline fim a fim
de 5,715 s. O maior valor fim a fim observado foi 389,826 ms.

## Artefatos

- `resultados/metricas/a2/A2_WCET_MEDIDO.csv`;
- `resultados/metricas/a2/A2_TABELA_TEMPORAL.csv`;
- `resultados/metricas/a2/A2_WCRT.csv`;
- `resultados/figuras/impressao/A2_WCET_VARIABILIDADE_COL.pdf`;
- `resultados/figuras/impressao/A2_WCRT_DEADLINES_COL.pdf`;
- `docs/ANALISE_WCET_WCRT.md`;
- `docs/TABELA_TEMPORAL.md`.

## Limitações

O resultado vale para o firmware, configuração FreeRTOS e frequência usados
nos ensaios. Não inclui prova estática no nível de instruções. Eventos de
falha foram excluídos da recorrência nominal e permanecem sustentados pelas
medições do E8.
