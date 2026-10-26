#include "control_core.hpp"

#include <math.h>
#include <string.h>

namespace strcontrol {
namespace {

constexpr double kPi = 3.141592653589793238462643383279502884;
constexpr double kTsSobre2 = 2.8575;
constexpr double kPwm16Max = 65535.0;

constexpr uint16_t kWEntrarCooler = 2000;
constexpr uint16_t kWSairCooler = 1000;
constexpr uint8_t kConfirmacoesModo = 2;

constexpr double kY0Nom = 50.50282999999999;
constexpr double kU0Nom = 9688.13559322;
constexpr double kNbNom = 1615.01542842;
constexpr double kKiNom = 55.87486056;
constexpr double kK1Nom = 2.42292827;
constexpr double kK2Nom = 37.30035107;
constexpr double kKqNom = 0.45467056;
constexpr double kCs1Nom = 1.30135744;
constexpr double kCs2Nom = 5.41983902;
constexpr double kGTermicoPwm16 = 455.85236927;
constexpr double kAd1 = 0.97680948204771745;
constexpr double kAd2 = 0.83799947890809312;
constexpr double kBd1 = 0.012391015895003424;
constexpr double kBd2 = 0.011491559879183539;

constexpr double kANom[4][4] = {
    {0.87148850627135255, -2.3349292179027987, 0.012391015895003424, 0},
    {-0.021460368525439675, 0.36223061019376079, 0.011491559879183539, 0},
    {0.54700065839072487, 12.12681339185988, 0.84668688848431295,
     5.4198390207695537},
    {0.098868116531183062, 2.1918715840409377, -0.052237956106038111,
     0.84668688848431295}};
constexpr double kBNom[4] = {0.012391015895003424, 0.011491559879183539, 0,
                              0};
constexpr double kLNom[4] = {101.15520303030875, 20.611544085060167,
                              -525.365078032665, -94.957574473786678};
constexpr double kCNom[2] = {0.0010411819918428509, 0.023082640812882287};

constexpr double kY0Cool = 50.0;
constexpr double kU0Cool = 29668.6850393701;
constexpr double kNbCool = 2157.30127859495;
constexpr double kKiCool = 74.6363818007599;
constexpr double kKxCool = 9.05232146430076;
constexpr double kKqCool = 0.368257902253556;
constexpr double kCCool = 0.00533973420046468;
constexpr double kCs1Cool = 1.214944790737869;
constexpr double kCs2Cool = 5.41983902076955;
constexpr double kBetaCoolSeno = 0.80;
constexpr double kFaseSeno = 2.940997279299572;

constexpr double kACool[3][3] = {
    {0.758025026798745, 0.0389974309184895, 0},
    {0, 0.846686888484313, 5.41983902076955},
    {0, -0.0522379561060381, 0.846686888484313}};
constexpr double kBCool[3] = {0.0389974309184895, 0, 0};
constexpr double kLCool[3] = {59.9192070008071, -1100.25874176182,
                               -100.465858001758};

}  // namespace

ControlCore::ControlCore() { reset(); }

void ControlCore::reset() {
  memset(&nominal_, 0, sizeof(nominal_));
  memset(&cooler_, 0, sizeof(cooler_));
  inicializado_ = false;
  modoCooler_ = false;
  contadorModo_ = 0;
  betaCoolerAtual_ = 1.0;
}

double ControlCore::limitar(double valor, double minimo, double maximo) {
  return fmin(fmax(valor, minimo), maximo);
}

double ControlCore::referencia(uint16_t indice) {
  return ((indice / 70U) % 2U == 0U) ? 45.0 : 55.0;
}

uint16_t ControlCore::comandoCooler(double tempoS) {
  if (tempoS < 1000.0) return 0U;
  if (tempoS < 1800.0 || tempoS >= 3000.0) return 3211U;

  const double seno =
      sin(2.0 * kPi * (tempoS - 1800.0) / 64.0 + kFaseSeno);
  double w = 3051.0 + 803.0 * seno;
  if (tempoS >= 2936.0) {
    const double alfa =
        0.5 * (1.0 + cos(kPi * (tempoS - 2936.0) / 64.0));
    w = 3211.0 + alfa * (w - 3211.0);
  }
  return static_cast<uint16_t>(limitar(w, 2248.0, 3854.0));
}

double ControlCore::pesoReferenciaCooler(double tempoS) {
  return (tempoS >= 1800.0 && tempoS < 3000.0) ? kBetaCoolSeno : 1.0;
}

void ControlCore::atualizarModo(uint16_t w) {
  const bool pedido =
      modoCooler_ ? (w > kWSairCooler) : (w >= kWEntrarCooler);
  if (pedido == modoCooler_) {
    contadorModo_ = 0;
    return;
  }
  if (++contadorModo_ >= kConfirmacoesModo) {
    modoCooler_ = pedido;
    contadorModo_ = 0;
  }
}

void ControlCore::atualizarPesoReferencia(double novoBeta, double r) {
  if (fabs(novoBeta - betaCoolerAtual_) < 1e-12) return;
  cooler_.xi += kNbCool * (betaCoolerAtual_ - novoBeta) * (r - kY0Cool) /
                kKiCool;
  betaCoolerAtual_ = novoBeta;
}

void ControlCore::alinharNominal(double y, double r, double us) {
  const double entradaEquivalente = (y - kY0Nom) * kGTermicoPwm16;
  nominal_.z[0] = kBd1 * entradaEquivalente / (1.0 - kAd1);
  nominal_.z[1] = kBd2 * entradaEquivalente / (1.0 - kAd2);
  nominal_.z[2] = 0;
  nominal_.z[3] = 0;
  nominal_.q = us - kU0Nom;
  nominal_.xi =
      (us - kU0Nom - kNbNom * (r - kY0Nom) + kK1Nom * nominal_.z[0] +
       kK2Nom * nominal_.z[1] + kKqNom * nominal_.q) /
      kKiNom;
  nominal_.erroAnterior = r - y;
  nominal_.referenciaAnterior = r;
  nominal_.correcaoAnterior = 0;
}

void ControlCore::alinharCooler(double y, double r, double us) {
  cooler_.z[0] = (y - kY0Cool) / kCCool;
  cooler_.z[1] = 0;
  cooler_.z[2] = 0;
  cooler_.q = us - kU0Cool;
  cooler_.xi =
      (us - kU0Cool - kNbCool * betaCoolerAtual_ * (r - kY0Cool) +
       kKxCool * cooler_.z[0] + kKqCool * cooler_.q) /
      kKiCool;
  cooler_.erroAnterior = r - y;
  cooler_.referenciaAnterior = r;
  cooler_.correcaoAnterior = 0;
}

void ControlCore::inicializarEstados(double y, double r) {
  alinharNominal(y, r, 0);
  alinharCooler(y, r, 0);
}

ControlCore::Candidato ControlCore::calcularNominal(double r, double y) const {
  const double erro = r - y;
  const double xi = nominal_.xi +
                    kTsSobre2 * (nominal_.erroAnterior +
                                 nominal_.referenciaAnterior - y) +
                    nominal_.correcaoAnterior;
  const double eSeno =
      kCs1Nom * nominal_.z[2] + kCs2Nom * nominal_.z[3];
  const double yEstimado =
      kCNom[0] * nominal_.z[0] + kCNom[1] * nominal_.z[1];
  const double uLivre =
      kU0Nom + kNbNom * (r - kY0Nom) + kKiNom * xi -
      kK1Nom * nominal_.z[0] - kK2Nom * nominal_.z[1] -
      kKqNom * nominal_.q - eSeno;
  return {erro, xi, uLivre, eSeno, y - kY0Nom - yEstimado};
}

ControlCore::Candidato ControlCore::calcularCooler(double r, double y) const {
  const double erro = r - y;
  const double xi = cooler_.xi +
                    kTsSobre2 *
                        (cooler_.erroAnterior + cooler_.referenciaAnterior - y) +
                    cooler_.correcaoAnterior;
  const double eSeno = kCs1Cool * cooler_.z[1] + kCs2Cool * cooler_.z[2];
  const double uLivre =
      kU0Cool + kNbCool * betaCoolerAtual_ * (r - kY0Cool) + kKiCool * xi -
      kKxCool * cooler_.z[0] - kKqCool * cooler_.q - eSeno;
  return {erro, xi, uLivre, eSeno,
          y - kY0Cool - kCCool * cooler_.z[0]};
}

void ControlCore::avancarNominal(const Candidato& c, double r, double y,
                                  double us) {
  double seguinte[4] = {};
  for (uint8_t i = 0; i < 4; ++i) {
    seguinte[i] = kBNom[i] * nominal_.q + kLNom[i] * (y - kY0Nom);
    for (uint8_t j = 0; j < 4; ++j) {
      seguinte[i] += kANom[i][j] * nominal_.z[j];
    }
  }
  for (uint8_t i = 0; i < 4; ++i) nominal_.z[i] = seguinte[i];
  nominal_.xi = c.xi;
  nominal_.erroAnterior = c.erro;
  nominal_.referenciaAnterior = r;
  nominal_.correcaoAnterior = (us - c.uLivre) / kKiNom;
  nominal_.q = us - kU0Nom;
}

void ControlCore::avancarCooler(const Candidato& c, double r, double us) {
  double seguinte[3] = {};
  for (uint8_t i = 0; i < 3; ++i) {
    seguinte[i] = kBCool[i] * cooler_.q + kLCool[i] * c.inovacao;
    for (uint8_t j = 0; j < 3; ++j) {
      seguinte[i] += kACool[i][j] * cooler_.z[j];
    }
  }
  for (uint8_t i = 0; i < 3; ++i) cooler_.z[i] = seguinte[i];
  cooler_.xi = c.xi;
  cooler_.erroAnterior = c.erro;
  cooler_.referenciaAnterior = r;
  cooler_.correcaoAnterior = (us - c.uLivre) / kKiCool;
  cooler_.q = us - kU0Cool;
}

SaidaControle ControlCore::step(uint16_t indice, double tempoS, double y) {
  const double r = referencia(indice);
  if (!inicializado_) {
    inicializarEstados(y, r);
    inicializado_ = true;
  }

  const uint16_t w = comandoCooler(tempoS);
  atualizarModo(w);
  atualizarPesoReferencia(pesoReferenciaCooler(tempoS), r);

  const Candidato cn = calcularNominal(r, y);
  const Candidato cc = calcularCooler(r, y);
  const double uLivre = modoCooler_ ? cc.uLivre : cn.uLivre;
  const double us = limitar(uLivre, 0.0, kPwm16Max);

  if (modoCooler_) {
    avancarCooler(cc, r, us);
    alinharNominal(y, r, us);
  } else {
    avancarNominal(cn, r, y, us);
    alinharCooler(y, r, us);
  }

  return {r,
          w,
          modoCooler_,
          betaCoolerAtual_,
          cn.uLivre,
          cc.uLivre,
          uLivre,
          us,
          cn.eSeno,
          cc.eSeno,
          cn.inovacao,
          cc.inovacao};
}

SaidaControle ControlCore::stepComCenario(double r, double y, uint16_t w,
                                          double beta) {
  if (!inicializado_) {
    inicializarEstados(y, r);
    inicializado_ = true;
  }

  atualizarModo(w);
  atualizarPesoReferencia(beta, r);

  const Candidato cn = calcularNominal(r, y);
  const Candidato cc = calcularCooler(r, y);
  const double uLivre = modoCooler_ ? cc.uLivre : cn.uLivre;
  const double us = limitar(uLivre, 0.0, kPwm16Max);

  if (modoCooler_) {
    avancarCooler(cc, r, us);
    alinharNominal(y, r, us);
  } else {
    avancarNominal(cn, r, y, us);
    alinharCooler(y, r, us);
  }

  return {r,
          w,
          modoCooler_,
          betaCoolerAtual_,
          cn.uLivre,
          cc.uLivre,
          uLivre,
          us,
          cn.eSeno,
          cc.eSeno,
          cn.inovacao,
          cc.inovacao};
}

}  // namespace strcontrol
