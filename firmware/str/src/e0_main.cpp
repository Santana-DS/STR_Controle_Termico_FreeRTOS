#include <Arduino.h>

#include "control_core.hpp"

#if !defined(STR_E0_REPLAY)
#error "Este firmware e exclusivamente o runner seguro do ensaio E0."
#endif

namespace {

strcontrol::ControlCore controle;
uint16_t indice = 0;

void reiniciar() {
  controle.reset();
  indice = 0;
  Serial.println("OK,RESET");
}

void executarPasso(const String& linha) {
  double tempoS = 0;
  double y = 0;
  if (sscanf(linha.c_str(), "STEP,%lf,%lf", &tempoS, &y) != 2 ||
      !isfinite(tempoS) || !isfinite(y)) {
    Serial.println("ERRO,STEP_INVALIDO");
    return;
  }

  const strcontrol::SaidaControle s = controle.step(indice, tempoS, y);
  Serial.printf(
      "OUT,%u,%.6f,%.10f,%u,%u,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f\n",
      indice, tempoS, s.referencia, s.cooler, s.modoCooler ? 1U : 0U,
      s.beta, s.uNominal, s.uCooler, s.uLivre, s.uSaturado,
      s.eSenoNominal, s.eSenoCooler, s.inovacaoNominal, s.inovacaoCooler);
  ++indice;
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(250);
  delay(250);
  Serial.println("READY,E0_REPLAY,SEM_ADC,SEM_PWM");
}

void loop() {
  if (Serial.available() <= 0) return;

  String linha = Serial.readStringUntil('\n');
  linha.trim();
  if (linha == "RESET") {
    reiniciar();
  } else if (linha == "PING") {
    Serial.println("OK,PONG");
  } else if (linha.startsWith("STEP,")) {
    executarPasso(linha);
  } else {
    Serial.println("ERRO,COMANDO_DESCONHECIDO");
  }
}
