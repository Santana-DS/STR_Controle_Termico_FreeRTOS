# Protocolo do ensaio E2

## Objetivo

Medir a latência de dois eventos esporádicos de segurança com a planta sem
alimentação de 12 V:

- `STOP` recebido pela UART, com deadline fim a fim de 100 ms;
- botão `BOOT`/GPIO 0 recebido por interrupção, com deadline de 50 ms.

## Caminho de software

```text
MATLAB -> UART -> T_Comunicacao -> fila de eventos
       -> T_Supervisao -> T_Atuacao -> saída segura simulada
```

O timestamp inicial é registrado no recebimento do comando `STOP`. O término
é registrado pela tarefa de atuação no ponto em que os PWMs seriam zerados.

## Caminho de hardware

```text
botão BOOT -> ISR GPIO 0 -> notificação FromISR
           -> T_Atuacao -> saída segura simulada
```

A ISR registra o instante, ativa o latch e notifica diretamente a tarefa de
maior prioridade. Não executa serial, controle ou ponto flutuante. Debounce e
rearmamento são tratados fora da ISR.

## Comandos adicionais

| Comando | Resposta | Regra |
|---|---|---|
| `ARM` | `ACK,ARM` | permitido somente com o sistema parado |
| `START` | `ACK,START` | recusado se a emergência continuar latched |

## Repetições e aceitação

- 20 repetições de `STOP` automáticas;
- 10 pressões manuais do botão `BOOT`;
- zero perda de deadline;
- zero descarte de trace;
- uma atuação segura para cada evento solicitado;
- nenhum tempo negativo ou sequência inconsistente.

## Resultado observado

As 20 repetições de `STOP` apresentaram latência máxima de 69 us, diante da
deadline de 100 ms. As 10 emergências pelo botão `BOOT` apresentaram máximo
de 17 us, diante da deadline de 50 ms. Não houve perdas nem descartes.
