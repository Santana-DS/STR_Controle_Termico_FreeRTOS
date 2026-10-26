# Firmware FreeRTOS

Implementação do controlador térmico como sistema de tempo real no ESP32. O
ambiente padrão do PlatformIO é `e3_nominal`, correspondente ao sistema físico
completo. Os demais ambientes isolam mecanismos específicos da arquitetura e
dos ensaios.

## Organização

- `src/main.cpp`: sistema nominal E3;
- `src/e*_main.cpp`: firmwares específicos dos demais ensaios;
- `lib/control_core`: núcleo do controlador independente de ADC, PWM e
  FreeRTOS;
- `platformio.ini`: seleção explícita dos ambientes de compilação.

## Ambientes

| Ambiente | Finalidade | ADC/PWM físico | Fonte de 12 V |
|---|---|---|---|
| `e0_replay` | equivalência do núcleo C++ | não | desligada |
| `e1_timing` | tarefas, filas e deadlines | não | desligada |
| `e2_safety` | `STOP` e interrupção pelo botão `BOOT` | não | desligada |
| `e3a_io_preflight` | aquisição real com saídas anuladas | ADC; PWM zero | desligada |
| `e3_nominal` | controle integrado da planta | sim | ligada e supervisionada |
| `e4_telemetry` | congestionamento da telemetria | sim | ligada e supervisionada |
| `e5_cpu_load` | carga progressiva com prioridade 1 | ADC; PWM zero | desligada |
| `e5b_priority` | comparação das prioridades 1 e 5 | ADC; PWM zero | desligada |
| `e6_switch` | transições nominal/cooler | sim | ligada e supervisionada |
| `e7_heartbeat` | perda de comunicação | não | desligada |
| `e8_fault_matrix` | matriz de cinco falhas | ADC; PWM zero | desligada |
| `e9_instrumentation` | custo da instrumentação | não | desligada |
| `e10_priority_inversion` | inversão e herança de prioridade | não | desligada |

## Arquitetura nominal

No núcleo 1, aquisição, controle, atuação, supervisão e watchdog executam com
prioridades fixas. No núcleo 0, comunicação e telemetria são desacopladas do
caminho crítico. As mensagens entre tarefas são copiadas por valor; o ADC é
protegido por mutex com herança de prioridade; somente `T_Atuacao` escreve nos
canais PWM.

A aquisição principal usa 128 conversões por sensor a cada 5,715 s. A
supervisão usa 64 conversões a cada 500 ms. O watchdog verifica a validade do
heartbeat a cada 5 ms, com timeout de 15 s. Sensor inválido, temperatura maior
ou igual a 60 °C, perda de heartbeat, `STOP`, emergência física ou falha das
filas críticas conduzem ao estado seguro.

Os comandos seriais, variáveis registradas e critérios de cada ensaio estão
descritos em `docs/PROTOCOLO_*.md`.
