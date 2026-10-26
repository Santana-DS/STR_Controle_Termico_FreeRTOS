#pragma once

#include <stdint.h>

namespace strcontrol {

struct SaidaControle {
  double referencia;
  uint16_t cooler;
  bool modoCooler;
  double beta;
  double uNominal;
  double uCooler;
  double uLivre;
  double uSaturado;
  double eSenoNominal;
  double eSenoCooler;
  double inovacaoNominal;
  double inovacaoCooler;
};

class ControlCore {
 public:
  ControlCore();

  void reset();
  SaidaControle step(uint16_t indice, double tempoS, double y);
  SaidaControle stepComCenario(double referencia, double y,
                               uint16_t cooler, double beta);

 private:
  struct EstadoNominal {
    double z[4];
    double xi;
    double erroAnterior;
    double referenciaAnterior;
    double correcaoAnterior;
    double q;
  };

  struct EstadoCooler {
    double z[3];
    double xi;
    double erroAnterior;
    double referenciaAnterior;
    double correcaoAnterior;
    double q;
  };

  struct Candidato {
    double erro;
    double xi;
    double uLivre;
    double eSeno;
    double inovacao;
  };

  EstadoNominal nominal_;
  EstadoCooler cooler_;
  bool inicializado_;
  bool modoCooler_;
  uint8_t contadorModo_;
  double betaCoolerAtual_;

  static double limitar(double valor, double minimo, double maximo);
  static double referencia(uint16_t indice);
  static uint16_t comandoCooler(double tempoS);
  static double pesoReferenciaCooler(double tempoS);

  void inicializarEstados(double y, double r);
  void atualizarModo(uint16_t w);
  void atualizarPesoReferencia(double novoBeta, double r);
  void alinharNominal(double y, double r, double us);
  void alinharCooler(double y, double r, double us);
  Candidato calcularNominal(double r, double y) const;
  Candidato calcularCooler(double r, double y) const;
  void avancarNominal(const Candidato& candidato, double r, double y,
                      double us);
  void avancarCooler(const Candidato& candidato, double r, double us);
};

}  // namespace strcontrol
