# Tabela temporal definitiva

## Núcleo crítico

| Tarefa | Ativação | `T_min` | Deadline | Prioridade | `C_obs` | Orçamento final | Bloqueio | WCRT |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `T_Atuacao` | comando ou alarme | 5,715 s no nominal | 20 ms | 8 | 93 us | 270 us, incluindo despacho | 0 | 270 us |
| `T_Watchdog` | varredura de heartbeat | 5 ms | 20 ms | 7 | 15 us | 20 us | 0 | 290 us por ativação |
| `T_Supervisao` | 500 ms ou evento | 500 ms | 500 ms | 6 | 77,976 ms | 82 ms | 325 ms | 408,910 ms |
| `T_Controle` | nova amostra | 5,715 s | 100 ms | 5 | 557 us | 600 us | 0 | 83,210 ms |
| `T_Aquisicao` | liberação periódica | 5,715 s | 600 ms | 4 | 311,216 ms ajustado | 330 ms | 0 | 414,530 ms |

`C_obs` da supervisão exclui espera no mutex. Na aquisição, a demanda própria
da supervisão sobreposta após a liberação do mutex também foi retirada para
evitar dupla contagem; as esperas ocupadas do ADC permanecem no orçamento. O
limite de detecção do watchdog é 5,290 ms: uma fase de varredura de 5 ms mais
290 us de WCRT da tarefa. O período atribuído às tarefas sucessoras vale para
o cenário nominal; eventos de segurança foram avaliados separadamente.

## Núcleo de comunicação e tarefas experimentais

| Tarefa | Núcleo | Tipo | Deadline | Evidência temporal | Tratamento |
|---|---:|---|---:|---:|---|
| `T_Comunicacao` | 0 | aperiódica | 100 ms | heartbeat: 21 us máx. | orçamento de projeto de 5 ms |
| `T_Telemetria` | 0 | aperiódica | 5,715 s, suave | formatação: 51,05 us máx. | orçamento de projeto de 25 ms; descartável |
| `T_Carga` | 1 | periódica de teste | configurável | calibrada por fase | suspensa na configuração nominal |

## Critério dos orçamentos

Os orçamentos do núcleo crítico incluem margem sobre o maior custo próprio
observado. Para a supervisão, execução e bloqueio pelo ADC são contabilizados
separadamente. Na aquisição, o valor de 330 ms cobre as 256 conversões e as
esperas ocupadas, cujo máximo ajustado foi 311,216 ms. Comunicação e
telemetria usam limites de projeto de 5 ms e 25 ms, respectivamente.
