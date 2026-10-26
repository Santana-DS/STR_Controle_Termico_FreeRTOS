# Firmware de referência

Implementação monolítica do controlador térmico desenvolvido no PRJ2 de
Controle Digital. O código corresponde à origem funcional das equações de
controle, dos observadores, do anti-windup e da lógica de troca de modo usados
na arquitetura FreeRTOS.

- código: `src/main.cpp`;
- alvo: ESP32 DevKit V1;
- configuração: `platformio.ini`;
- projeto de origem:
  [CDig_PRJ_Grupo10](https://github.com/Santana-DS/CDig_PRJ_Grupo10).

A implementação concorrente e os firmwares dos ensaios estão em `../str`.
