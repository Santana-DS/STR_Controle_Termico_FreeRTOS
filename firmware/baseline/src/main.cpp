// PRJ2 - refinamento comparativo do controle escalonado (1 hora).
// Mantem em paralelo o controlador nominal (cooler desligado) e o
// controlador P1D identificado com W=3211. O controlador inativo rastreia
// o PWM aplicado, permitindo transferencia sem salto de comando.

#include <Arduino.h>
#include <math.h>

namespace prj2 {

// Hardware, amostragem e seguranca.
constexpr uint8_t kPinTp = 36;
constexpr uint8_t kPinTa = 34;
constexpr uint8_t kPinAquecedor = 25;
constexpr uint8_t kPinCooler = 26;
constexpr uint8_t kCanalAquecedor = 0;
constexpr uint8_t kCanalCooler = 2;
constexpr uint16_t kConversoesAdc = 128;
constexpr uint32_t kTsMs = 5715;
constexpr double kTsSobre2 = 2.8575;
constexpr uint32_t kDuracaoMs = 3600000;  // Ensaio final de 1 hora.
constexpr uint32_t kTimeoutComunicacaoMs = 15000;
constexpr double kTemperaturaCorteC = 60.0;
constexpr double kPwm16Max = 65535.0;

// O modo muda somente apos duas amostras consecutivas alem do limiar.
constexpr uint16_t kWEntrarCooler = 2000;
constexpr uint16_t kWSairCooler = 1000;
constexpr uint8_t kConfirmacoesModo = 2;

// Controlador nominal: modelo P2DZ sem cooler.
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
    {0.54700065839072487, 12.12681339185988, 0.84668688848431295, 5.4198390207695537},
    {0.098868116531183062, 2.1918715840409377, -0.052237956106038111, 0.84668688848431295}};
constexpr double kBNom[4] = {0.012391015895003424, 0.011491559879183539, 0, 0};
constexpr double kLNom[4] = {101.15520303030875, 20.611544085060167,
                              -525.365078032665, -94.957574473786678};
constexpr double kCNom[2] = {0.0010411819918428509, 0.023082640812882287};

// Controlador P1D identificado com cooler constante W=3211.
constexpr double kY0Cool = 50.0;
constexpr double kU0Cool = 29668.6850393701;
constexpr double kNbCool = 2157.30127859495;
constexpr double kKiCool = 74.6363818007599;
constexpr double kKxCool = 9.05232146430076;
constexpr double kKqCool = 0.368257902253556;
constexpr double kCCool = 0.00533973420046468;
constexpr double kCs1Cool = 1.214944790737869;  // Kq + Fd(1,1).
constexpr double kCs2Cool = 5.41983902076955;
constexpr double kBetaCoolSeno = 0.80;  // Ponderacao de R somente com senoide.
constexpr double kFaseSeno = 2.940997279299572;  // Inicio continuo e descendente.

constexpr double kACool[3][3] = {
    {0.758025026798745, 0.0389974309184895, 0},
    {0, 0.846686888484313, 5.41983902076955},
    {0, -0.0522379561060381, 0.846686888484313}};
constexpr double kBCool[3] = {0.0389974309184895, 0, 0};
constexpr double kLCool[3] = {59.9192070008071, -1100.25874176182,
                               -100.465858001758};

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

EstadoNominal nominal;
EstadoCooler cooler;
bool coletando = false;
bool estadosInicializados = false;
bool modoCooler = false;
uint8_t contadorModo = 0;
uint32_t inicioMs = 0;
uint32_t proximaAmostraMs = 0;
uint32_t ultimaComunicacaoMs = 0;
uint16_t indice = 0;
double betaCoolerAtual = 1.0;

double limitar(double valor, double minimo, double maximo) {
  return fmin(fmax(valor, minimo), maximo);
}

void desligarAtuadores() {
  ledcWrite(kCanalAquecedor, 0);
  ledcWrite(kCanalCooler, 0);
}

double lerTemperatura(uint8_t pino) {
  double somaMv = 0;
  for (uint16_t i = 0; i < kConversoesAdc; ++i) {
    somaMv += analogReadMilliVolts(pino);
    delayMicroseconds(1000);
  }
  return somaMv / (10.0 * kConversoesAdc);  // LM35: 10 mV/grau C.
}

double referencia(uint16_t amostra) {
  return ((amostra / 70U) % 2U == 0U) ? 45.0 : 55.0;
}

uint16_t comandoCooler(double tempoS) {
  // O cooler e acionado em t=1000 s, durante o patamar de 45 graus C.
  // Em 1800 s, a perturbacao passa a ser senoidal; apos 3000 s, volta
  // ao valor constante usado na identificacao da planta com cooler.
  if (tempoS < 1000.0) return 0U;
  if (tempoS < 1800.0 || tempoS >= 3000.0) return 3211U;
  // Preserva W(1800)=3211 e inicia reduzindo o PWM, como na simulacao.
  const double seno = sin(2.0 * PI * (tempoS - 1800.0) / 64.0 + kFaseSeno);
  double w = 3051.0 + 803.0 * seno;
  if (tempoS >= 2936.0) {
    // Janela cossenoidal no ultimo periodo: chega a W=3211 em 3000 s
    // sem o degrau que contaminou o fim da senoide no ensaio anterior.
    const double alfa = 0.5 * (1.0 + cos(PI * (tempoS - 2936.0) / 64.0));
    w = 3211.0 + alfa * (w - 3211.0);
  }
  return static_cast<uint16_t>(limitar(w, 2248.0, 3854.0));
}

double pesoReferenciaCooler(double tempoS) {
  return (tempoS >= 1800.0 && tempoS < 3000.0) ? kBetaCoolSeno : 1.0;
}

void atualizarPesoReferencia(double novoBeta, double r) {
  if (fabs(novoBeta - betaCoolerAtual) < 1e-12) return;
  // Compensa xi para que a troca de beta nao altere instantaneamente U.
  cooler.xi += kNbCool * (betaCoolerAtual - novoBeta) *
      (r - kY0Cool) / kKiCool;
  betaCoolerAtual = novoBeta;
}

void atualizarModo(uint16_t w) {
  const bool pedido = modoCooler ? (w > kWSairCooler) : (w >= kWEntrarCooler);
  if (pedido == modoCooler) {
    contadorModo = 0;
    return;
  }
  if (++contadorModo >= kConfirmacoesModo) {
    modoCooler = pedido;
    contadorModo = 0;
  }
}

void alinharNominal(double y, double r, double us) {
  // Reconstrói um estado nominal coerente com Y e com o PWM real.
  const double entradaEquivalente = (y - kY0Nom) * kGTermicoPwm16;
  nominal.z[0] = kBd1 * entradaEquivalente / (1.0 - kAd1);
  nominal.z[1] = kBd2 * entradaEquivalente / (1.0 - kAd2);
  nominal.z[2] = 0;
  nominal.z[3] = 0;
  nominal.q = us - kU0Nom;
  nominal.xi = (us - kU0Nom - kNbNom * (r - kY0Nom) +
      kK1Nom * nominal.z[0] + kK2Nom * nominal.z[1] +
      kKqNom * nominal.q) / kKiNom;
  nominal.erroAnterior = r - y;
  nominal.referenciaAnterior = r;
  nominal.correcaoAnterior = 0;
}

void alinharCooler(double y, double r, double us) {
  // O modelo P1D não evolui enquanto o cooler está desligado: seus estados
  // são preparados diretamente para reproduzir o PWM aplicado.
  cooler.z[0] = (y - kY0Cool) / kCCool;
  cooler.z[1] = 0;
  cooler.z[2] = 0;
  cooler.q = us - kU0Cool;
  cooler.xi = (us - kU0Cool - kNbCool * betaCoolerAtual * (r - kY0Cool) +
      kKxCool * cooler.z[0] + kKqCool * cooler.q) / kKiCool;
  cooler.erroAnterior = r - y;
  cooler.referenciaAnterior = r;
  cooler.correcaoAnterior = 0;
}

void inicializarEstados(double y, double r) {
  alinharNominal(y, r, 0);
  alinharCooler(y, r, 0);
}

Candidato calcularNominal(double r, double y) {
  const double erro = r - y;
  const double xi = nominal.xi + kTsSobre2 *
      (nominal.erroAnterior + nominal.referenciaAnterior - y) +
      nominal.correcaoAnterior;
  const double eSeno = kCs1Nom * nominal.z[2] + kCs2Nom * nominal.z[3];
  const double yEstimado = kCNom[0] * nominal.z[0] + kCNom[1] * nominal.z[1];
  const double uLivre = kU0Nom + kNbNom * (r - kY0Nom) + kKiNom * xi -
      kK1Nom * nominal.z[0] - kK2Nom * nominal.z[1] -
      kKqNom * nominal.q - eSeno;
  return {erro, xi, uLivre, eSeno, y - kY0Nom - yEstimado};
}

Candidato calcularCooler(double r, double y) {
  const double erro = r - y;
  const double xi = cooler.xi + kTsSobre2 *
      (cooler.erroAnterior + cooler.referenciaAnterior - y) +
      cooler.correcaoAnterior;
  const double eSeno = kCs1Cool * cooler.z[1] + kCs2Cool * cooler.z[2];
  const double uLivre = kU0Cool + kNbCool * betaCoolerAtual *
      (r - kY0Cool) + kKiCool * xi -
      kKxCool * cooler.z[0] - kKqCool * cooler.q - eSeno;
  return {erro, xi, uLivre, eSeno, y - kY0Cool - kCCool * cooler.z[0]};
}

void avancarNominal(const Candidato& c, double r, double y, double us) {
  double seguinte[4] = {};
  for (uint8_t i = 0; i < 4; ++i) {
    seguinte[i] = kBNom[i] * nominal.q + kLNom[i] * (y - kY0Nom);
    for (uint8_t j = 0; j < 4; ++j) seguinte[i] += kANom[i][j] * nominal.z[j];
  }
  for (uint8_t i = 0; i < 4; ++i) nominal.z[i] = seguinte[i];
  nominal.xi = c.xi;
  nominal.erroAnterior = c.erro;
  nominal.referenciaAnterior = r;
  nominal.correcaoAnterior = (us - c.uLivre) / kKiNom;
  nominal.q = us - kU0Nom;
}

void avancarCooler(const Candidato& c, double r, double us) {
  double seguinte[3] = {};
  for (uint8_t i = 0; i < 3; ++i) {
    seguinte[i] = kBCool[i] * cooler.q + kLCool[i] * c.inovacao;
    for (uint8_t j = 0; j < 3; ++j) seguinte[i] += kACool[i][j] * cooler.z[j];
  }
  for (uint8_t i = 0; i < 3; ++i) cooler.z[i] = seguinte[i];
  cooler.xi = c.xi;
  cooler.erroAnterior = c.erro;
  cooler.referenciaAnterior = r;
  cooler.correcaoAnterior = (us - c.uLivre) / kKiCool;
  cooler.q = us - kU0Cool;
}

void encerrar(const char* motivo) {
  coletando = false;
  desligarAtuadores();
  Serial.println(motivo);
  Serial.println("END_DATA");
}

void iniciar() {
  desligarAtuadores();
  indice = 0;
  estadosInicializados = false;
  modoCooler = false;
  contadorModo = 0;
  betaCoolerAtual = 1.0;
  inicioMs = millis();
  proximaAmostraMs = inicioMs;
  ultimaComunicacaoMs = inicioMs;
  coletando = true;
  Serial.println("START_DATA");
  Serial.println("CONFIG,PRJ2,REFINAMENTO_1H,Ts=5.715,Tcorte=60,Wconst=3211,Wseno_fase=2.940997,taper=64,beta_seno=0.80,W_on=2000,W_off=1000,N=2");
  Serial.println("t,R,Y,Ta,W,modo,beta,U_nom,U_cool,U_livre,Us,e_sin_nom,e_sin_cool,inov_nom,inov_cool");
}

}  // namespace prj2

void setup() {
  using namespace prj2;
  digitalWrite(kPinAquecedor, LOW);
  digitalWrite(kPinCooler, LOW);
  pinMode(kPinAquecedor, OUTPUT);
  pinMode(kPinCooler, OUTPUT);
  Serial.begin(115200);
  Serial.setTimeout(100);

  const uint32_t fa = ledcSetup(kCanalAquecedor, 1000, 16);
  const uint32_t fc = ledcSetup(kCanalCooler, 5000, 12);
  if (fa == 0 || fc == 0) {
    Serial.println("ALARME_CONFIG_PWM");
    return;
  }
  ledcAttachPin(kPinAquecedor, kCanalAquecedor);
  ledcAttachPin(kPinCooler, kCanalCooler);
  desligarAtuadores();

  analogReadResolution(12);
  analogSetPinAttenuation(kPinTp, ADC_0db);
  analogSetPinAttenuation(kPinTa, ADC_0db);
  Serial.println("READY: PRJ2_CONTROLE_ESCALONADO");
  // O RESET fisico define t=0 sem depender de comando manual. Se o
  // coletor nao assumir a comunicacao, o timeout desliga os atuadores.
  iniciar();
}

void loop() {
  using namespace prj2;

  if (!coletando) desligarAtuadores();
  if (Serial.available() > 0) {
    String comando = Serial.readStringUntil('\n');
    comando.trim();
    if (comando == "START" && !coletando) iniciar();
    else if (comando == "STOP" && coletando) encerrar("PARADA_MANUAL");
    else if (comando == "HEARTBEAT" && coletando) ultimaComunicacaoMs = millis();
  }
  if (!coletando) return;

  const uint32_t agoraMs = millis();
  if (agoraMs - ultimaComunicacaoMs > kTimeoutComunicacaoMs) {
    encerrar("ALARME_COMUNICACAO");
    return;
  }
  if (agoraMs - inicioMs >= kDuracaoMs) {
    encerrar("FIM_NORMAL");
    return;
  }
  if (static_cast<int32_t>(agoraMs - proximaAmostraMs) < 0) return;

  const double tempoS = (agoraMs - inicioMs) / 1000.0;
  const double y = lerTemperatura(kPinTp);
  const double ta = lerTemperatura(kPinTa);
  if (!isfinite(y) || !isfinite(ta) || y < -10 || y > 100 || ta < -10 || ta > 100) {
    encerrar("ALARME_SENSOR");
    return;
  }
  if (y >= kTemperaturaCorteC) {
    encerrar("ALARME_TEMPERATURA_PROCESSO");
    return;
  }

  const double r = referencia(indice);
  if (!estadosInicializados) {
    inicializarEstados(y, r);
    estadosInicializados = true;
  }
  const uint16_t w = comandoCooler(tempoS);
  atualizarModo(w);
  atualizarPesoReferencia(pesoReferenciaCooler(tempoS), r);
  const Candidato cn = calcularNominal(r, y);
  const Candidato cc = calcularCooler(r, y);
  const double uLivre = modoCooler ? cc.uLivre : cn.uLivre;
  const double us = limitar(uLivre, 0.0, kPwm16Max);

  // Somente o observador compatível com a planta ativa evolui. O outro é
  // realinhado a Y e Us, evitando estados espúrios antes da próxima troca.
  if (modoCooler) {
    avancarCooler(cc, r, us);
    alinharNominal(y, r, us);
  } else {
    avancarNominal(cn, r, y, us);
    alinharCooler(y, r, us);
  }
  ledcWrite(kCanalAquecedor, static_cast<uint32_t>(us));
  ledcWrite(kCanalCooler, w);

  Serial.printf("%.3f,%.4f,%.4f,%.4f,%u,%u,%.2f,%.4f,%.4f,%.4f,%.0f,%.4f,%.4f,%.4f,%.4f\n",
      tempoS, r, y, ta, w, modoCooler ? 1U : 0U, betaCoolerAtual,
      cn.uLivre, cc.uLivre, uLivre, us, cn.eSeno, cc.eSeno,
      cn.inovacao, cc.inovacao);
  ++indice;
  proximaAmostraMs += kTsMs;
}
