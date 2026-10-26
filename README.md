# Sistema de tempo real para controle de planta térmica

Implementação em ESP32/FreeRTOS de uma arquitetura de tempo real para o
controlador térmico desenvolvido no PRJ2 de Controle Digital.

O controlador validado no PRJ2 é tratado como baseline funcional. Este
projeto concentra-se em decomposição em tarefas, escalonamento, sincronização,
segurança, instrumentação temporal e avaliação experimental.

## Principais resultados

- equivalência do núcleo de controle verificada em 634 amostras;
- ensaio físico nominal de 1 h com 630 transações, 899 heartbeats e nenhuma
  perda de deadline;
- cadeia aquisição--controle--atuação limitada analiticamente a 498,010 ms,
  ou 8,71% da deadline fim a fim de 5,715 s;
- maior utilização local de deadline: 83,21% no controle;
- telemetria congestionada sem interrupção do caminho crítico;
- prioridade inadequada produzindo três perdas locais da aquisição em E5b;
- 25 transições para estado seguro verificadas em E8;
- espera mediana de 16,731 ms com mutex e herança contra 58,405 ms com
  semáforo binário no E10.

Os limites de execução empregados na análise são experimentais e não
constituem uma prova estática de WCET.

## Hardware e ferramentas

- ESP32 DevKit V1, dois LM35, aquecedor resistivo e cooler de 12 V;
- PlatformIO com framework Arduino para ESP32;
- MATLAB para coleta, validação e geração das figuras.

## Estrutura

| Diretório | Conteúdo |
|---|---|
| [`docs`](docs) | requisitos, arquitetura, protocolos e análise temporal |
| [`firmware`](firmware) | baseline e ambientes FreeRTOS |
| [`matlab`](matlab) | coletores, validadores e sínteses offline |
| [`resultados`](resultados) | traces, métricas e figuras dos ensaios |

## Documentação técnica

- [`docs/REQUISITOS_STR.md`](docs/REQUISITOS_STR.md): requisitos funcionais,
  temporais, de concorrência e instrumentação;
- [`docs/ARQUITETURA_STR.md`](docs/ARQUITETURA_STR.md): tarefas, prioridades,
  precedências, interrupções e propriedade dos recursos;
- [`docs/TABELA_TEMPORAL.md`](docs/TABELA_TEMPORAL.md): parâmetros temporais
  consolidados;
- [`docs/ANALISE_WCET_WCRT.md`](docs/ANALISE_WCET_WCRT.md): limites
  experimentais e análise de resposta;
- [`docs/METODOLOGIA_EXPERIMENTAL.md`](docs/METODOLOGIA_EXPERIMENTAL.md):
  cenários, variáveis medidas e critérios de análise;
- [`docs/BASELINE_CONTROLE.md`](docs/BASELINE_CONTROLE.md): origem e elementos
  funcionais preservados do PRJ2.

## Referência de controle

A baseline provém do projeto
[CDig_PRJ_Grupo10](https://github.com/Santana-DS/CDig_PRJ_Grupo10), em
`PRJ2/firmware/final/src/main.cpp`. A versão incorporada e seus elementos
funcionais são descritos em [`docs/BASELINE_CONTROLE.md`](docs/BASELINE_CONTROLE.md).

## Experimentos validados

| ID | Ambiente PlatformIO | Evidência principal |
|---|---|---|
| E0 | `e0_replay` | equivalência numérica do núcleo C++ |
| E1 | `e1_timing` | tarefas, precedências, jitter e deadlines |
| E2 | `e2_safety` | `STOP` e interrupção pelo botão `BOOT` |
| E3a | `e3a_io_preflight` | ADC real e saídas físicas em zero |
| E3 | `e3_nominal` | operação nominal da planta por 1 h |
| E4 | `e4_telemetry` | congestionamento não bloqueante |
| E5/E5b | `e5_cpu_load` / `e5b_priority` | carga e sensibilidade à prioridade |
| E6 | `e6_switch` | transições entre controladores |
| E7 | `e7_heartbeat` | perda de heartbeat |
| E8 | `e8_fault_matrix` | matriz de cinco caminhos de falha |
| E9 | `e9_instrumentation` | custo da instrumentação |
| E10 | `e10_priority_inversion` | inversão e herança de prioridade |

## Autoria

Lucas Santana da Silva — Universidade de Brasília, CIC0248 — Sistemas de
Tempo Real, 2/2026.
