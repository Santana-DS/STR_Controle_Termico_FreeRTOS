# Protocolo E8 — matriz de falhas do sistema físico completo

## Objetivo

Validar no firmware com ADC e PWM configurados os cinco caminhos de transição
para o estado seguro:

1. comando aperiódico `STOP`;
2. sensor inválido injetado;
3. sobretemperatura injetada;
4. perda de heartbeat;
5. interrupção física pelo botão `BOOT`.

## Segurança

O ensaio é executado com os 12 V desligados. Cada repetição inicia o caminho
completo de aquisição, controle e atuação, aguarda o primeiro comando e então
provoca a falha. O critério de saída segura é `PWM_heat = PWM_cool = 0`.

As injeções existem somente no ambiente `e8_fault_matrix`. Elas atravessam a
fila de eventos, são classificadas pela supervisão com as mesmas regras de
validade e limite térmico e acionam o latch comum. Nenhum comando de injeção
faz parte do ambiente nominal.

## Procedimento

O coletor executa cinco repetições por caminho. `STOP`, sensor, temperatura e
heartbeat são automáticos. Nas cinco últimas repetições, o operador pressiona
e solta `BOOT` quando solicitado. Enquanto aguarda a ação manual, o coletor
renova o heartbeat a cada 4 s para impedir que o watchdog antecipe a falha sob
teste. Na etapa dedicada à perda de heartbeat, essa renovação é suspensa.

## Critérios

- 25 eventos completos;
- PWM zero após cada evento;
- nenhuma perda das deadlines associadas;
- zero descarte de trace;
- detecção e atuação relacionadas pela mesma sequência;
- estado final parado e seguro.

## Resultado observado

O ensaio `E8` apresentou 25 eventos completos, PWM
zero após todas as falhas, nenhuma perda de deadline, nenhum descarte e estado
final seguro.
