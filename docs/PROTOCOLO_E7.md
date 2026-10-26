# Protocolo do ensaio E7

## Objetivo

Validar o desligamento seguro quando o computador deixa de enviar heartbeat,
mantendo a planta sem alimentação de 12 V.

## Requisito temporal

- timeout nominal: 15 s após o último `HEARTBEAT` válido;
- verificação do watchdog: a cada 5 ms;
- deadline da detecção até a atuação segura simulada: 50 ms.

O instante de vencimento é calculado no recebimento do heartbeat. `START`,
`STATUS`, telemetria e demais comandos não renovam esse instante.

## Caminho

```text
HEARTBEAT -> T_Comunicacao -> estado protegido
ausência por 15 s -> T_Watchdog -> notificação direta
                  -> T_Atuacao -> saída segura simulada
```

`HB_RX` registra cada renovação explícita. `DET_HB` mede a detecção a partir
do vencimento nominal. `ATUA_HB` mede o caminho completo do vencimento até a
atuação segura.

## Protocolo serial

| Comando | Resposta | Regra |
|---|---|---|
| `ARM_HB` | `ACK,ARM_HB` | arma uma repetição com o sistema parado |
| `HEARTBEAT` | `ACK,HEARTBEAT` | única operação que renova o timeout |
| `START` | `ACK,START` | exige heartbeat ativo e latch liberado |

## Repetições e aceitação

- 10 repetições automáticas;
- 4 heartbeats explícitos por repetição;
- diferença exata de 15.000.000 us entre o último `HB_RX` e o vencimento;
- uma detecção e uma atuação para cada perda de comunicação;
- sequências contínuas, sem perdas de deadline ou descartes de trace.

## Resultado observado

Nas 10 repetições, o timeout nominal de 15 s foi respeitado. A maior latência
entre o vencimento e a atuação segura foi 4,442 ms, correspondente a 8,884%
da deadline de 50 ms. Não ocorreram perdas ou descartes.
