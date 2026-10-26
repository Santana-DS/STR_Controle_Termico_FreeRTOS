# Analise

Scripts MATLAB usados para validar logs, calcular métricas e gerar os
artefatos apresentados em `../resultados`.

## Ensaios disponiveis

- `e0_replay_baseline.m`: reexecuta o algoritmo do PRJ2 usando o ensaio final
  gravado e quantifica a diferenca causada pela precisao limitada do CSV.
- `e0_validar_core_serial.m`: envia as 634 amostras ao runner E0 na ESP32 e
  compara os 12 sinais do núcleo C++ com o oráculo do PRJ2;
- `e1_coletar_timing.m`: controla o runner E1, coleta o trace temporal, gera
  percentis e falha automaticamente diante de tempos negativos, deadlines
  perdidos ou descarte de telemetria;
- `e2_coletar_seguranca.m`: repete automaticamente o caminho de `STOP`, guia
  os acionamentos do botão `BOOT` e valida as latências dos dois caminhos de
  segurança;
- `e7_coletar_heartbeat.m`: envia heartbeats explícitos, interrompe sua
  renovação e valida o timeout de 15 s, a detecção e a atuação segura.
- `e3a_validar_io_passivo.m`: coleta 30 aquisições físicas dos dois LM35,
  valida a deadline de 600 ms e confirma que ambos os PWM ficaram em zero.
- `e3_coletar_nominal.m`: conduz o E3, renova o heartbeat, salva dados e
  trace, valida precedências, deadlines, contadores internos e encerramento
  seguro; sem argumentos executa o comissionamento de 60 s na `COM3`. O
  monitor gráfico em tempo real mostra temperaturas e comandos PWM e salva
  uma imagem PNG ao final.
- `e4_coletar_congestionamento.m`: suspende o consumo da telemetria, valida
  saturação e descartes contabilizados sem bloquear o caminho crítico;
- `e5_coletar_carga.m`: executa cinco patamares de carga nominal no núcleo
  crítico, valida cada fase e gera gráficos temporais e funcionais;
- `e5b_coletar_prioridades.m`: repete os cinco patamares nas prioridades 1 e
  5, valida a igualdade do trabalho por ciclo e compara interferência,
  jitter, tempos de resposta e perdas locais da aquisição;
- `e6_coletar_troca.m`: valida as quatro transições entre os controladores
  nominal e cooler e quantifica a continuidade da atuação.
- `e9_coletar_instrumentacao.m`: mede e apresenta média, percentis e máximo
  dos mecanismos usados para timestamps, traces, filas e contadores.
- `e8_coletar_matriz_falhas.m`: repete cinco vezes cada caminho de falha,
  associa detecção e atuação, valida deadlines e confirma os PWM em zero.
- `e10_coletar_inversao_prioridade.m`: coleta 30 repetições de três cenários,
  valida a herança de prioridade e compara a espera da tarefa alta.
- `a1_sintese_temporal.m`: lê os resultados validados e regenera o
  diagrama temporal do E3 e o painel consolidado de E5b, E8, E9 e E10.
- `a1_figuras_impressao.m`: gera PDFs vetoriais e PNGs em escala IEEE para a
  síntese A1.
- `a2_analise_wcet_wcrt.m`: consolida distribuições de execução, constrói a
  tabela temporal, calcula WCRT por prioridade fixa e gera as figuras A2.
