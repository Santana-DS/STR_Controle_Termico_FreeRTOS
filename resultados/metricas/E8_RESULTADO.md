# E8 — matriz de falhas e atuação segura

## Resultado

O ensaio desenergizado `E8` executou cinco repetições de
cada caminho de falha: `STOP`, sensor inválido, sobretemperatura, perda de
heartbeat e botão físico `BOOT`. Os 25 eventos conduziram o sistema ao estado
parado com os dois PWM em zero.

| Falha | Repetições | Média | P95 | Máximo | Deadline |
|---|---:|---:|---:|---:|---:|
| `STOP` | 5 | 76,4 us | 85 us | 85 us | 100.000 us |
| sensor inválido | 5 | 78,4 us | 88 us | 91 us | 100.000 us |
| sobretemperatura | 5 | 5.591,8 us | 20.996,4 us | 26.051 us | 100.000 us |
| perda de heartbeat | 5 | 3.671,2 us | 4.472 us | 4.472 us | 50.000 us |
| botão `BOOT` | 5 | 32,2 us | 40,4 us | 41 us | 50.000 us |

Não houve perda de deadline local ou fim a fim, descarte de trace ou estado
final inseguro. O arquivo contém 360 registros temporais, incluindo os 25
caminhos completos de desligamento.

## Interpretação

O botão `BOOT`, ligado diretamente ao caminho de interrupção e à tarefa de
atuação, apresentou a menor latência. `STOP` e sensor inválido também foram
tratados em menos de 0,1 ms. A perda de heartbeat inclui a varredura periódica
do watchdog e ainda conservou margem superior a 45 ms.

A terceira repetição de sobretemperatura apresentou 26,051 ms porque a tarefa
de supervisão iniciou aproximadamente 25,7 ms após a liberação do evento. Esse
é um efeito real do escalonamento, permaneceu abaixo da deadline de 100 ms e
não afetou as demais repetições. O resultado demonstra tanto a correção dos
cinco caminhos quanto sua margem temporal no hardware utilizado.
