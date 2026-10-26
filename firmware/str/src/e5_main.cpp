#include <Arduino.h>

#include <math.h>
#include <stdarg.h>
#include <string.h>

#include "control_core.hpp"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#if !defined(STR_E5_CPU_LOAD)
#error "Este arquivo pertence exclusivamente ao ensaio E5 de carga."
#endif

namespace {

constexpr uint8_t kPinTp = 36;
constexpr uint8_t kPinTa = 34;
constexpr uint8_t kPinAquecedor = 25;
constexpr uint8_t kPinCooler = 26;
constexpr uint8_t kCanalAquecedor = 0;
constexpr uint8_t kCanalCooler = 2;
constexpr uint8_t kPinoEmergencia = 0;
constexpr uint16_t kConversoesAdc = 128;
constexpr uint16_t kConversoesSupervisao = 64;

constexpr uint32_t kPeriodoControleMs = 5715;
constexpr int64_t kPeriodoControleUs = 5715000;
constexpr uint32_t kPeriodoSupervisaoMs = 500;
constexpr int64_t kPeriodoSupervisaoUs = 500000;
constexpr int64_t kDeadlineAquisicaoUs = 600000;
constexpr int64_t kDeadlineControleUs = 100000;
constexpr int64_t kDeadlineAtuacaoUs = 20000;
constexpr int64_t kDeadlineSupervisaoUs = 500000;
constexpr int64_t kDeadlineFimAFimUs = 5715000;
constexpr int64_t kDeadlineStopUs = 100000;
constexpr int64_t kDeadlineEmergenciaUs = 50000;
constexpr int64_t kTimeoutHeartbeatUs = 15000000;
constexpr int64_t kDeadlineHeartbeatUs = 50000;
constexpr int64_t kDeadlineDeteccaoHeartbeatUs = 20000;
constexpr uint32_t kPeriodoWatchdogMs = 5;
constexpr int64_t kDebounceEmergenciaUs = 200000;
constexpr double kTemperaturaCorteC = 60.0;
constexpr uint32_t kDuracaoPadraoS = 600;
constexpr uint32_t kDuracaoMinimaS = 600;
constexpr uint32_t kDuracaoMaximaS = 600;
constexpr uint8_t kQuantidadeFasesCarga = 5;
constexpr uint8_t kCargasPercentuais[kQuantidadeFasesCarga] = {0, 10, 25, 40, 60};
constexpr uint32_t kDuracaoFaseCargaS = 120;
constexpr uint32_t kPeriodoCargaUs = 20000;

constexpr EventBits_t kBitExecutando = BIT0;

struct Amostra {
  uint32_t sequencia;
  double tempoS;
  double tpC;
  double taC;
  int64_t liberacaoUs;
  int64_t terminoUs;
};

struct ComandoAtuacao {
  uint32_t sequencia;
  double tempoS;
  double tpC;
  double taC;
  strcontrol::SaidaControle saida;
  int64_t aquisicaoFimUs;
  int64_t liberacaoLocalUs;
  int64_t origemFimAFimUs;
};

enum class TipoEvento : uint8_t { Stop = 1 };

struct EventoSistema {
  TipoEvento tipo;
  uint32_t sequencia;
  int64_t instanteUs;
};

enum class MotivoEncerramento : uint8_t {
  Nenhum = 0,
  ParadaManual,
  FimNormal,
  SensorInvalido,
  Sobretemperatura,
  FalhaAdc,
  Deadline,
  FilaAmostra,
  FilaComando
};

struct EncerramentoPendente {
  MotivoEncerramento motivo;
  uint32_t sequencia;
  int64_t origemUs;
  int64_t deteccaoUs;
  int64_t deadlineUs;
};

struct RegistroTrace {
  char tarefa[16];
  uint32_t sequencia;
  int64_t liberacaoUs;
  int64_t inicioUs;
  int64_t terminoUs;
  int64_t deadlineUs;
  int64_t jitterUs;
  int64_t execucaoUs;
  int64_t respostaUs;
  uint8_t perdeuDeadline;
  int64_t respostaFimAFimUs;
  int64_t deadlineFimAFimUs;
  uint8_t perdeuDeadlineFimAFim;
  int64_t bloqueioUs;
  uint16_t ocupacaoFilaTrace;
  uint32_t descartesTrace;
};

struct RegistroDados {
  uint32_t sequencia;
  double tempoS;
  double referencia;
  double tpC;
  double taC;
  uint16_t cooler;
  uint8_t modoCooler;
  double beta;
  double uNominal;
  double uCooler;
  double uLivre;
  double uSaturado;
  double eSenoNominal;
  double eSenoCooler;
  double inovacaoNominal;
  double inovacaoCooler;
  int64_t liberacaoUs;
  int64_t aquisicaoFimUs;
  int64_t controleFimUs;
  int64_t atuacaoUs;
};

struct Mensagem {
  char texto[96];
};

struct Contadores {
  uint32_t traceDescartado;
  uint32_t dadosDescartados;
  uint32_t mensagemDescartada;
  uint32_t amostraDescartada;
  uint32_t comandoDescartado;
  uint32_t eventoDescartado;
};

struct ResumoFaseCarga {
  uint32_t jobsAquisicao;
  uint32_t jobsControle;
  uint32_t jobsAtuacao;
  uint32_t jobsSupervisao;
  uint32_t perdasDeadline;
  int64_t jitterAquisicaoMaxUs;
  int64_t jitterSupervisaoMaxUs;
  int64_t respostaAquisicaoMaxUs;
  int64_t respostaControleMaxUs;
  int64_t respostaAtuacaoMaxUs;
  int64_t respostaSupervisaoMaxUs;
  int64_t respostaFimAFimMaxUs;
  uint32_t ciclosCarga;
  uint64_t orcamentoCargaTotalUs;
  int64_t janelaCargaMaxUs;
};

QueueHandle_t filaAmostras = nullptr;
QueueHandle_t filaComandos = nullptr;
QueueHandle_t filaEventos = nullptr;
QueueHandle_t filaTrace = nullptr;
QueueHandle_t filaDados = nullptr;
QueueHandle_t filaMensagens = nullptr;
SemaphoreHandle_t mutexAdc = nullptr;
SemaphoreHandle_t mutexSerial = nullptr;
EventGroupHandle_t estadoSistema = nullptr;
TaskHandle_t tarefaAquisicao = nullptr;
TaskHandle_t tarefaAtuacao = nullptr;

portMUX_TYPE muxContadores = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE muxResumoCarga = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE muxEstado = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE muxEmergencia = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE muxHeartbeat = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE muxEncerramento = portMUX_INITIALIZER_UNLOCKED;

Contadores contadores{};
ResumoFaseCarga resumosCarga[kQuantidadeFasesCarga]{};
strcontrol::ControlCore controle;
bool hardwareOk = false;
uint32_t sequenciaStop = 0;
uint32_t sequenciaEmergencia = 0;
uint32_t sequenciaHeartbeat = 0;
uint32_t sequenciaHeartbeatRecebido = 0;

volatile int64_t inicioEnsaioUs = 0;
volatile int64_t fimEnsaioUs = 0;
volatile bool emergenciaArmada = false;
volatile bool emergenciaLatched = false;
volatile bool emergenciaPendente = false;
volatile int64_t instanteEmergenciaUs = 0;
volatile int64_t ultimoPulsoEmergenciaUs = 0;
volatile bool heartbeatArmado = false;
volatile bool heartbeatAtivo = false;
volatile bool heartbeatLatched = false;
volatile bool heartbeatPendente = false;
volatile int64_t vencimentoHeartbeatUs = 0;
volatile int64_t deteccaoHeartbeatUs = 0;
volatile uint32_t sequenciaHeartbeatPendente = 0;
volatile bool encerramentoLatched = false;
volatile bool encerramentoPendente = false;
EncerramentoPendente encerramento{};
volatile uint32_t acumuladorCarga = 1U;

bool executando() {
  return (xEventGroupGetBits(estadoSistema) & kBitExecutando) != 0;
}

void definirJanelaEnsaio(int64_t inicioUs, int64_t fimUs) {
  portENTER_CRITICAL(&muxEstado);
  inicioEnsaioUs = inicioUs;
  fimEnsaioUs = fimUs;
  portEXIT_CRITICAL(&muxEstado);
}

void copiarJanelaEnsaio(int64_t* inicioUs, int64_t* fimUs) {
  portENTER_CRITICAL(&muxEstado);
  *inicioUs = inicioEnsaioUs;
  *fimUs = fimEnsaioUs;
  portEXIT_CRITICAL(&muxEstado);
}

void zerarContadores() {
  portENTER_CRITICAL(&muxContadores);
  memset(&contadores, 0, sizeof(contadores));
  portEXIT_CRITICAL(&muxContadores);
}

void incrementar(uint32_t* contador) {
  portENTER_CRITICAL(&muxContadores);
  ++(*contador);
  portEXIT_CRITICAL(&muxContadores);
}

Contadores copiarContadores() {
  portENTER_CRITICAL(&muxContadores);
  const Contadores copia = contadores;
  portEXIT_CRITICAL(&muxContadores);
  return copia;
}

void zerarResumosCarga() {
  portENTER_CRITICAL(&muxResumoCarga);
  memset(resumosCarga, 0, sizeof(resumosCarga));
  portEXIT_CRITICAL(&muxResumoCarga);
}

ResumoFaseCarga copiarResumoCarga(uint8_t fase) {
  portENTER_CRITICAL(&muxResumoCarga);
  const ResumoFaseCarga copia = resumosCarga[fase];
  portEXIT_CRITICAL(&muxResumoCarga);
  return copia;
}

bool obterFaseCarga(int64_t instanteUs, uint8_t* fase) {
  int64_t inicioUs = 0;
  int64_t fimUs = 0;
  copiarJanelaEnsaio(&inicioUs, &fimUs);
  if (inicioUs <= 0 || instanteUs < inicioUs || instanteUs >= fimUs) return false;
  const uint32_t decorridoS =
      static_cast<uint32_t>((instanteUs - inicioUs) / 1000000);
  uint8_t calculada = static_cast<uint8_t>(decorridoS / kDuracaoFaseCargaS);
  if (calculada >= kQuantidadeFasesCarga) calculada = kQuantidadeFasesCarga - 1;
  *fase = calculada;
  return true;
}

void atualizarResumoCarga(const RegistroTrace& r) {
  if (!executando()) return;
  uint8_t fase = 0;
  if (!obterFaseCarga(r.inicioUs, &fase)) return;

  portENTER_CRITICAL(&muxResumoCarga);
  ResumoFaseCarga& s = resumosCarga[fase];
  bool critica = false;
  if (strcmp(r.tarefa, "AQUISICAO") == 0) {
    ++s.jobsAquisicao;
    if (r.jitterUs > s.jitterAquisicaoMaxUs) s.jitterAquisicaoMaxUs = r.jitterUs;
    if (r.respostaUs > s.respostaAquisicaoMaxUs)
      s.respostaAquisicaoMaxUs = r.respostaUs;
    critica = true;
  } else if (strcmp(r.tarefa, "CONTROLE") == 0) {
    ++s.jobsControle;
    if (r.respostaUs > s.respostaControleMaxUs)
      s.respostaControleMaxUs = r.respostaUs;
    critica = true;
  } else if (strcmp(r.tarefa, "ATUACAO") == 0) {
    ++s.jobsAtuacao;
    if (r.respostaUs > s.respostaAtuacaoMaxUs)
      s.respostaAtuacaoMaxUs = r.respostaUs;
    if (r.respostaFimAFimUs > s.respostaFimAFimMaxUs)
      s.respostaFimAFimMaxUs = r.respostaFimAFimUs;
    critica = true;
  } else if (strcmp(r.tarefa, "SUPERVISAO") == 0) {
    ++s.jobsSupervisao;
    if (r.jitterUs > s.jitterSupervisaoMaxUs) s.jitterSupervisaoMaxUs = r.jitterUs;
    if (r.respostaUs > s.respostaSupervisaoMaxUs)
      s.respostaSupervisaoMaxUs = r.respostaUs;
    critica = true;
  }
  if (critica && (r.perdeuDeadline || r.perdeuDeadlineFimAFim))
    ++s.perdasDeadline;
  portEXIT_CRITICAL(&muxResumoCarga);
}

void registrarCicloCarga(uint8_t fase, uint32_t orcamentoUs,
                         int64_t janelaUs) {
  portENTER_CRITICAL(&muxResumoCarga);
  ResumoFaseCarga& s = resumosCarga[fase];
  ++s.ciclosCarga;
  s.orcamentoCargaTotalUs += orcamentoUs;
  if (janelaUs > s.janelaCargaMaxUs) s.janelaCargaMaxUs = janelaUs;
  portEXIT_CRITICAL(&muxResumoCarga);
}

void imprimirSerial(const char* formato, ...) {
  char linha[512];
  va_list argumentos;
  va_start(argumentos, formato);
  vsnprintf(linha, sizeof(linha), formato, argumentos);
  va_end(argumentos);
  if (xSemaphoreTake(mutexSerial, pdMS_TO_TICKS(100)) == pdTRUE) {
    Serial.println(linha);
    xSemaphoreGive(mutexSerial);
  }
}

void enfileirarMensagem(const char* formato, ...) {
  Mensagem mensagem{};
  va_list argumentos;
  va_start(argumentos, formato);
  vsnprintf(mensagem.texto, sizeof(mensagem.texto), formato, argumentos);
  va_end(argumentos);
  if (xQueueSend(filaMensagens, &mensagem, 0) != pdTRUE) {
    incrementar(&contadores.mensagemDescartada);
  }
}

void registrarTrace(const char* tarefa, uint32_t sequencia,
                    int64_t liberacaoUs, int64_t inicioUs, int64_t terminoUs,
                    int64_t deadlineUs, int64_t origemFimAFimUs = -1,
                    int64_t deadlineFimAFimUs = 0, int64_t bloqueioUs = 0) {
  RegistroTrace r{};
  strncpy(r.tarefa, tarefa, sizeof(r.tarefa) - 1);
  r.sequencia = sequencia;
  r.liberacaoUs = liberacaoUs;
  r.inicioUs = inicioUs;
  r.terminoUs = terminoUs;
  r.deadlineUs = deadlineUs;
  r.jitterUs = inicioUs - liberacaoUs;
  r.execucaoUs = terminoUs - inicioUs;
  r.respostaUs = terminoUs - liberacaoUs;
  r.perdeuDeadline = r.respostaUs > deadlineUs;
  r.respostaFimAFimUs =
      origemFimAFimUs >= 0 ? terminoUs - origemFimAFimUs : -1;
  r.deadlineFimAFimUs = deadlineFimAFimUs;
  r.perdeuDeadlineFimAFim =
      deadlineFimAFimUs > 0 && r.respostaFimAFimUs > deadlineFimAFimUs;
  r.bloqueioUs = bloqueioUs;
  r.ocupacaoFilaTrace = uxQueueMessagesWaiting(filaTrace);
  r.descartesTrace = copiarContadores().traceDescartado;
  atualizarResumoCarga(r);
  if (xQueueSend(filaTrace, &r, 0) != pdTRUE) {
    incrementar(&contadores.traceDescartado);
  }
}

const char* nomeMotivo(MotivoEncerramento motivo) {
  switch (motivo) {
    case MotivoEncerramento::ParadaManual: return "PARADA_MANUAL";
    case MotivoEncerramento::FimNormal: return "FIM_NORMAL";
    case MotivoEncerramento::SensorInvalido: return "SENSOR_INVALIDO";
    case MotivoEncerramento::Sobretemperatura: return "SOBRETEMPERATURA";
    case MotivoEncerramento::FalhaAdc: return "FALHA_ADC";
    case MotivoEncerramento::Deadline: return "DEADLINE";
    case MotivoEncerramento::FilaAmostra: return "FILA_AMOSTRA";
    case MotivoEncerramento::FilaComando: return "FILA_COMANDO";
    default: return "NENHUM";
  }
}

bool encerramentoEstaLatched() {
  portENTER_CRITICAL(&muxEncerramento);
  const bool ativo = encerramentoLatched;
  portEXIT_CRITICAL(&muxEncerramento);
  return ativo;
}

void armarEncerramento() {
  portENTER_CRITICAL(&muxEncerramento);
  encerramentoLatched = false;
  encerramentoPendente = false;
  encerramento = {};
  portEXIT_CRITICAL(&muxEncerramento);
}

void solicitarEncerramento(MotivoEncerramento motivo, uint32_t sequencia,
                            int64_t origemUs, int64_t deteccaoUs,
                            int64_t deadlineUs) {
  bool aceito = false;
  portENTER_CRITICAL(&muxEncerramento);
  if (!encerramentoLatched) {
    encerramentoLatched = true;
    encerramentoPendente = true;
    encerramento = {motivo, sequencia, origemUs, deteccaoUs, deadlineUs};
    aceito = true;
  }
  portEXIT_CRITICAL(&muxEncerramento);
  if (aceito) {
    xEventGroupClearBits(estadoSistema, kBitExecutando);
    xTaskNotifyGive(tarefaAtuacao);
  }
}

bool consumirEncerramento(EncerramentoPendente* copia) {
  portENTER_CRITICAL(&muxEncerramento);
  const bool pendente = encerramentoPendente;
  if (pendente) {
    *copia = encerramento;
    encerramentoPendente = false;
  }
  portEXIT_CRITICAL(&muxEncerramento);
  return pendente;
}

bool emergenciaEstaLatched() {
  portENTER_CRITICAL(&muxEmergencia);
  const bool ativa = emergenciaLatched;
  portEXIT_CRITICAL(&muxEmergencia);
  return ativa;
}

void armarEmergencia() {
  portENTER_CRITICAL(&muxEmergencia);
  emergenciaPendente = false;
  emergenciaLatched = false;
  emergenciaArmada = true;
  ultimoPulsoEmergenciaUs = 0;
  portEXIT_CRITICAL(&muxEmergencia);
}

bool consumirEmergencia(int64_t* instanteUs, uint32_t* sequencia) {
  portENTER_CRITICAL(&muxEmergencia);
  const bool pendente = emergenciaPendente;
  if (pendente) {
    *instanteUs = instanteEmergenciaUs;
    *sequencia = sequenciaEmergencia++;
    emergenciaPendente = false;
  }
  portEXIT_CRITICAL(&muxEmergencia);
  return pendente;
}

bool heartbeatEstaAtivo() {
  portENTER_CRITICAL(&muxHeartbeat);
  const bool ativo = heartbeatAtivo;
  portEXIT_CRITICAL(&muxHeartbeat);
  return ativo;
}

bool heartbeatEstaLatched() {
  portENTER_CRITICAL(&muxHeartbeat);
  const bool ativo = heartbeatLatched;
  portEXIT_CRITICAL(&muxHeartbeat);
  return ativo;
}

void armarHeartbeat() {
  portENTER_CRITICAL(&muxHeartbeat);
  heartbeatArmado = true;
  heartbeatAtivo = false;
  heartbeatLatched = false;
  heartbeatPendente = false;
  vencimentoHeartbeatUs = 0;
  deteccaoHeartbeatUs = 0;
  portEXIT_CRITICAL(&muxHeartbeat);
}

bool renovarHeartbeat(int64_t agoraUs) {
  portENTER_CRITICAL(&muxHeartbeat);
  const bool aceito = heartbeatArmado && !heartbeatLatched;
  if (aceito) {
    heartbeatAtivo = true;
    vencimentoHeartbeatUs = agoraUs + kTimeoutHeartbeatUs;
  }
  portEXIT_CRITICAL(&muxHeartbeat);
  return aceito;
}

bool consumirFalhaHeartbeat(int64_t* vencimentoUs, int64_t* deteccaoUs,
                            uint32_t* sequencia) {
  portENTER_CRITICAL(&muxHeartbeat);
  const bool pendente = heartbeatPendente;
  if (pendente) {
    *vencimentoUs = vencimentoHeartbeatUs;
    *deteccaoUs = deteccaoHeartbeatUs;
    *sequencia = sequenciaHeartbeatPendente;
    heartbeatPendente = false;
  }
  portEXIT_CRITICAL(&muxHeartbeat);
  return pendente;
}

bool segurancaEstaLatched() {
  return emergenciaEstaLatched() || heartbeatEstaLatched() ||
         encerramentoEstaLatched();
}

void escreverPwm(uint16_t aquecedor, uint16_t cooler) {
  ledcWrite(kCanalAquecedor, aquecedor);
  ledcWrite(kCanalCooler, cooler);
}

double lerTemperatura(uint8_t pino, uint16_t conversoes) {
  double somaMv = 0.0;
  for (uint16_t i = 0; i < conversoes; ++i) {
    somaMv += analogReadMilliVolts(pino);
    delayMicroseconds(1000);
  }
  return somaMv / (10.0 * conversoes);
}

bool temperaturaValida(double valor) {
  return isfinite(valor) && valor >= -10.0 && valor <= 100.0;
}

void tarefaDeAquisicao(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    TickType_t ultimaLiberacao = xTaskGetTickCount();
    int64_t liberacaoEsperadaUs = esp_timer_get_time();
    uint32_t sequencia = 0;

    while (executando()) {
      const int64_t inicioUs = esp_timer_get_time();
      const int64_t liberacaoUs =
          inicioUs < liberacaoEsperadaUs ? inicioUs : liberacaoEsperadaUs;
      const int64_t pedidoAdcUs = esp_timer_get_time();
      double tpC = NAN;
      double taC = NAN;
      int64_t bloqueioAdcUs = 0;
      bool obteveAdc = false;
      if (xSemaphoreTake(mutexAdc, pdMS_TO_TICKS(550)) == pdTRUE) {
        const int64_t posseAdcUs = esp_timer_get_time();
        bloqueioAdcUs = posseAdcUs - pedidoAdcUs;
        tpC = lerTemperatura(kPinTp, kConversoesAdc);
        taC = lerTemperatura(kPinTa, kConversoesAdc);
        xSemaphoreGive(mutexAdc);
        obteveAdc = true;
      }
      const int64_t terminoUs = esp_timer_get_time();

      registrarTrace("AQUISICAO", sequencia, liberacaoUs, inicioUs,
                     terminoUs, kDeadlineAquisicaoUs, -1, 0, bloqueioAdcUs);
      if (!obteveAdc) {
        solicitarEncerramento(MotivoEncerramento::FalhaAdc, sequencia,
                              terminoUs, terminoUs, kDeadlineEmergenciaUs);
        break;
      }
      if (!temperaturaValida(tpC) || !temperaturaValida(taC)) {
        solicitarEncerramento(MotivoEncerramento::SensorInvalido, sequencia,
                              terminoUs, terminoUs, kDeadlineEmergenciaUs);
        break;
      }
      if (tpC >= kTemperaturaCorteC) {
        enfileirarMensagem(
            "EVENT,ALARM,SOBRETEMPERATURA,AQUISICAO,%.6f", tpC);
        solicitarEncerramento(MotivoEncerramento::Sobretemperatura, sequencia,
                              terminoUs, terminoUs, kDeadlineEmergenciaUs);
        break;
      }
      if (terminoUs - liberacaoUs > kDeadlineAquisicaoUs) {
        solicitarEncerramento(MotivoEncerramento::Deadline, sequencia,
                              liberacaoUs, terminoUs, kDeadlineAquisicaoUs);
        break;
      }

      int64_t inicioEnsaio = 0;
      int64_t fimEnsaio = 0;
      copiarJanelaEnsaio(&inicioEnsaio, &fimEnsaio);
      (void)fimEnsaio;
      if (!executando()) break;
      Amostra amostra{sequencia,
                      static_cast<double>(inicioUs - inicioEnsaio) / 1.0e6,
                      tpC, taC, liberacaoUs, terminoUs};
      if (xQueueSend(filaAmostras, &amostra, 0) != pdTRUE) {
        incrementar(&contadores.amostraDescartada);
        solicitarEncerramento(MotivoEncerramento::FilaAmostra, sequencia,
                              liberacaoUs, esp_timer_get_time(),
                              kDeadlineFimAFimUs);
        break;
      }

      ++sequencia;
      vTaskDelayUntil(&ultimaLiberacao, pdMS_TO_TICKS(kPeriodoControleMs));
      liberacaoEsperadaUs += kPeriodoControleUs;
    }
  }
}

void tarefaDeControle(void*) {
  Amostra amostra{};
  for (;;) {
    if (xQueueReceive(filaAmostras, &amostra, portMAX_DELAY) != pdTRUE) continue;
    if (!executando()) continue;
    const int64_t inicioUs = esp_timer_get_time();
    if (amostra.sequencia == 0) controle.reset();
    const strcontrol::SaidaControle saida = controle.step(
        static_cast<uint16_t>(amostra.sequencia), amostra.tempoS, amostra.tpC);
    const int64_t terminoUs = esp_timer_get_time();

    registrarTrace("CONTROLE", amostra.sequencia, amostra.terminoUs,
                   inicioUs, terminoUs, kDeadlineControleUs,
                   amostra.liberacaoUs, kDeadlineFimAFimUs);
    if (terminoUs - amostra.terminoUs > kDeadlineControleUs) {
      solicitarEncerramento(MotivoEncerramento::Deadline, amostra.sequencia,
                            amostra.terminoUs, terminoUs,
                            kDeadlineControleUs);
      continue;
    }

    ComandoAtuacao comando{amostra.sequencia, amostra.tempoS, amostra.tpC,
                           amostra.taC, saida, amostra.terminoUs, terminoUs,
                           amostra.liberacaoUs};
    if (xQueueSend(filaComandos, &comando, 0) != pdTRUE) {
      incrementar(&contadores.comandoDescartado);
      solicitarEncerramento(MotivoEncerramento::FilaComando,
                            amostra.sequencia, amostra.liberacaoUs,
                            esp_timer_get_time(), kDeadlineFimAFimUs);
    } else {
      xTaskNotifyGive(tarefaAtuacao);
    }
  }
}

void enfileirarDados(const ComandoAtuacao& comando, int64_t atuacaoUs) {
  RegistroDados d{};
  d.sequencia = comando.sequencia;
  d.tempoS = comando.tempoS;
  d.referencia = comando.saida.referencia;
  d.tpC = comando.tpC;
  d.taC = comando.taC;
  d.cooler = comando.saida.cooler;
  d.modoCooler = comando.saida.modoCooler ? 1U : 0U;
  d.beta = comando.saida.beta;
  d.uNominal = comando.saida.uNominal;
  d.uCooler = comando.saida.uCooler;
  d.uLivre = comando.saida.uLivre;
  d.uSaturado = comando.saida.uSaturado;
  d.eSenoNominal = comando.saida.eSenoNominal;
  d.eSenoCooler = comando.saida.eSenoCooler;
  d.inovacaoNominal = comando.saida.inovacaoNominal;
  d.inovacaoCooler = comando.saida.inovacaoCooler;
  d.liberacaoUs = comando.origemFimAFimUs;
  d.aquisicaoFimUs = comando.aquisicaoFimUs;
  d.controleFimUs = comando.liberacaoLocalUs;
  d.atuacaoUs = atuacaoUs;
  if (xQueueSend(filaDados, &d, 0) != pdTRUE) {
    incrementar(&contadores.dadosDescartados);
  }
}

void tarefaDeAtuacao(void*) {
  ComandoAtuacao comando{};
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

    int64_t instanteEventoUs = 0;
    uint32_t sequenciaEvento = 0;
    if (consumirEmergencia(&instanteEventoUs, &sequenciaEvento)) {
      const int64_t inicioUs = esp_timer_get_time();
      xEventGroupClearBits(estadoSistema, kBitExecutando);
      escreverPwm(0, 0);
      const int64_t terminoUs = esp_timer_get_time();
      xQueueReset(filaComandos);
      registrarTrace("ATUA_EMERG", sequenciaEvento, instanteEventoUs,
                     inicioUs, terminoUs, kDeadlineEmergenciaUs,
                     instanteEventoUs, kDeadlineEmergenciaUs);
      enfileirarMensagem("EVENT,END,EMERGENCIA");
    }

    int64_t vencimentoHeartbeat = 0;
    int64_t deteccaoHeartbeat = 0;
    uint32_t sequenciaFalhaHeartbeat = 0;
    if (consumirFalhaHeartbeat(&vencimentoHeartbeat, &deteccaoHeartbeat,
                               &sequenciaFalhaHeartbeat)) {
      const int64_t inicioUs = esp_timer_get_time();
      escreverPwm(0, 0);
      const int64_t terminoUs = esp_timer_get_time();
      xQueueReset(filaComandos);
      registrarTrace("ATUA_HB", sequenciaFalhaHeartbeat,
                     deteccaoHeartbeat, inicioUs, terminoUs,
                     kDeadlineAtuacaoUs, vencimentoHeartbeat,
                     kDeadlineHeartbeatUs);
      enfileirarMensagem("EVENT,END,HEARTBEAT");
    }

    EncerramentoPendente fim{};
    if (consumirEncerramento(&fim)) {
      const int64_t inicioUs = esp_timer_get_time();
      escreverPwm(0, 0);
      const int64_t terminoUs = esp_timer_get_time();
      xQueueReset(filaComandos);
      const char* tarefa = fim.motivo == MotivoEncerramento::ParadaManual
                                ? "ATUA_STOP"
                            : fim.motivo == MotivoEncerramento::FimNormal
                                ? "ATUA_FIM"
                                : "ATUA_SAFE";
      registrarTrace(tarefa, fim.sequencia, fim.deteccaoUs, inicioUs,
                     terminoUs, kDeadlineAtuacaoUs, fim.origemUs,
                     fim.deadlineUs);
      enfileirarMensagem("EVENT,END,%s", nomeMotivo(fim.motivo));
    }

    while (xQueueReceive(filaComandos, &comando, 0) == pdTRUE) {
      if (!executando() || segurancaEstaLatched()) continue;
      const int64_t inicioUs = esp_timer_get_time();
      escreverPwm(static_cast<uint16_t>(comando.saida.uSaturado),
                  comando.saida.cooler);
      const int64_t terminoUs = esp_timer_get_time();
      registrarTrace("ATUACAO", comando.sequencia,
                     comando.liberacaoLocalUs, inicioUs, terminoUs,
                     kDeadlineAtuacaoUs, comando.origemFimAFimUs,
                     kDeadlineFimAFimUs);
      enfileirarDados(comando, terminoUs);
      if (terminoUs - comando.liberacaoLocalUs > kDeadlineAtuacaoUs ||
          terminoUs - comando.origemFimAFimUs > kDeadlineFimAFimUs) {
        solicitarEncerramento(MotivoEncerramento::Deadline,
                              comando.sequencia, comando.origemFimAFimUs,
                              terminoUs, kDeadlineFimAFimUs);
      }
    }
  }
}

void tarefaDeWatchdogComunicacao(void*) {
  TickType_t ultimaLiberacao = xTaskGetTickCount();
  const TickType_t periodo = pdMS_TO_TICKS(kPeriodoWatchdogMs);
  for (;;) {
    vTaskDelayUntil(&ultimaLiberacao, periodo);
    const int64_t inicioUs = esp_timer_get_time();
    bool disparou = false;
    int64_t vencimentoUs = 0;
    uint32_t sequencia = 0;
    portENTER_CRITICAL(&muxHeartbeat);
    if (heartbeatAtivo && !heartbeatLatched &&
        inicioUs >= vencimentoHeartbeatUs) {
      heartbeatAtivo = false;
      heartbeatArmado = false;
      heartbeatLatched = true;
      heartbeatPendente = true;
      deteccaoHeartbeatUs = inicioUs;
      sequenciaHeartbeatPendente = sequenciaHeartbeat++;
      vencimentoUs = vencimentoHeartbeatUs;
      sequencia = sequenciaHeartbeatPendente;
      disparou = true;
    }
    portEXIT_CRITICAL(&muxHeartbeat);
    if (disparou) {
      xEventGroupClearBits(estadoSistema, kBitExecutando);
      const int64_t terminoUs = esp_timer_get_time();
      registrarTrace("DET_HB", sequencia, vencimentoUs, inicioUs,
                     terminoUs, kDeadlineDeteccaoHeartbeatUs, vencimentoUs,
                     kDeadlineHeartbeatUs);
      xTaskNotifyGive(tarefaAtuacao);
    }
  }
}

void IRAM_ATTR isrEmergencia() {
  const int64_t agoraUs = esp_timer_get_time();
  bool aceito = false;
  portENTER_CRITICAL_ISR(&muxEmergencia);
  if (emergenciaArmada && !emergenciaLatched &&
      (ultimoPulsoEmergenciaUs == 0 ||
       agoraUs - ultimoPulsoEmergenciaUs >= kDebounceEmergenciaUs)) {
    ultimoPulsoEmergenciaUs = agoraUs;
    instanteEmergenciaUs = agoraUs;
    emergenciaPendente = true;
    emergenciaLatched = true;
    emergenciaArmada = false;
    aceito = true;
  }
  portEXIT_CRITICAL_ISR(&muxEmergencia);
  if (aceito && tarefaAtuacao != nullptr) {
    BaseType_t acordar = pdFALSE;
    vTaskNotifyGiveFromISR(tarefaAtuacao, &acordar);
    if (acordar == pdTRUE) portYIELD_FROM_ISR();
  }
}

void tratarStop(const EventoSistema& evento) {
  const int64_t inicioUs = esp_timer_get_time();
  solicitarEncerramento(MotivoEncerramento::ParadaManual, evento.sequencia,
                        evento.instanteUs, inicioUs, kDeadlineStopUs);
  const int64_t terminoUs = esp_timer_get_time();
  registrarTrace("SUP_STOP", evento.sequencia, evento.instanteUs, inicioUs,
                 terminoUs, kDeadlineStopUs, evento.instanteUs,
                 kDeadlineStopUs);
}

void tarefaDeSupervisao(void*) {
  const TickType_t periodo = pdMS_TO_TICKS(kPeriodoSupervisaoMs);
  TickType_t proximaLiberacao = xTaskGetTickCount() + periodo;
  int64_t liberacaoEsperadaUs = 0;
  bool referenciaTemporalDefinida = false;
  uint32_t sequencia = 0;
  EventoSistema evento{};

  for (;;) {
    const TickType_t agora = xTaskGetTickCount();
    const TickType_t espera =
        static_cast<int32_t>(proximaLiberacao - agora) > 0
            ? proximaLiberacao - agora
            : 0;
    if (xQueueReceive(filaEventos, &evento, espera) == pdTRUE) {
      if (evento.tipo == TipoEvento::Stop) tratarStop(evento);
      continue;
    }

    const int64_t inicioUs = esp_timer_get_time();
    if (!referenciaTemporalDefinida) {
      liberacaoEsperadaUs = inicioUs;
      referenciaTemporalDefinida = true;
    }
    const int64_t liberacaoUs =
        inicioUs < liberacaoEsperadaUs ? inicioUs : liberacaoEsperadaUs;
    int64_t bloqueioAdcUs = 0;
    double tpRapida = NAN;
    bool obteveAdc = true;

    if (executando()) {
      const int64_t pedidoAdcUs = esp_timer_get_time();
      obteveAdc = xSemaphoreTake(mutexAdc, pdMS_TO_TICKS(400)) == pdTRUE;
      if (obteveAdc) {
        bloqueioAdcUs = esp_timer_get_time() - pedidoAdcUs;
        tpRapida = lerTemperatura(kPinTp, kConversoesSupervisao);
        xSemaphoreGive(mutexAdc);
      }
      const int64_t agoraUs = esp_timer_get_time();
      int64_t inicioEnsaio = 0;
      int64_t fimEnsaio = 0;
      copiarJanelaEnsaio(&inicioEnsaio, &fimEnsaio);
      (void)inicioEnsaio;
      if (!obteveAdc) {
        solicitarEncerramento(MotivoEncerramento::FalhaAdc, sequencia,
                              agoraUs, agoraUs, kDeadlineEmergenciaUs);
      } else if (!temperaturaValida(tpRapida)) {
        solicitarEncerramento(MotivoEncerramento::SensorInvalido, sequencia,
                              agoraUs, agoraUs, kDeadlineEmergenciaUs);
      } else if (tpRapida >= kTemperaturaCorteC) {
        enfileirarMensagem(
            "EVENT,ALARM,SOBRETEMPERATURA,SUPERVISAO,%.6f", tpRapida);
        solicitarEncerramento(MotivoEncerramento::Sobretemperatura, sequencia,
                              agoraUs, agoraUs, kDeadlineEmergenciaUs);
      } else if (agoraUs >= fimEnsaio) {
        solicitarEncerramento(MotivoEncerramento::FimNormal, sequencia,
                              fimEnsaio, agoraUs, kDeadlineAquisicaoUs);
      }
    }

    const int64_t terminoUs = esp_timer_get_time();
    registrarTrace("SUPERVISAO", sequencia++, liberacaoUs, inicioUs,
                   terminoUs, kDeadlineSupervisaoUs, -1, 0, bloqueioAdcUs);
    proximaLiberacao += periodo;
    liberacaoEsperadaUs += kPeriodoSupervisaoUs;
  }
}

void imprimirStatus() {
  const Contadores c = copiarContadores();
  imprimirSerial(
      "STATUS,E5,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u",
      executando() ? 1U : 0U, hardwareOk ? 1U : 0U,
      segurancaEstaLatched() ? 1U : 0U, heartbeatEstaAtivo() ? 1U : 0U,
      ledcRead(kCanalAquecedor), ledcRead(kCanalCooler),
      static_cast<unsigned>(uxQueueMessagesWaiting(filaAmostras)),
      static_cast<unsigned>(uxQueueMessagesWaiting(filaComandos)),
      static_cast<unsigned>(uxQueueMessagesWaiting(filaTrace)),
      c.traceDescartado, c.dadosDescartados, c.mensagemDescartada,
      c.amostraDescartada, c.comandoDescartado, c.eventoDescartado);
}

void imprimirResumoCarga(uint8_t fase) {
  const ResumoFaseCarga s = copiarResumoCarga(fase);
  imprimirSerial(
      "SUMMARY,E5,%u,%u,%u,%u,%u,%u,%u,%lld,%lld,%lld,%lld,%lld,%lld,%lld,%u,%llu,%lld",
      fase, kCargasPercentuais[fase], s.jobsAquisicao, s.jobsControle,
      s.jobsAtuacao, s.jobsSupervisao, s.perdasDeadline,
      static_cast<long long>(s.jitterAquisicaoMaxUs),
      static_cast<long long>(s.jitterSupervisaoMaxUs),
      static_cast<long long>(s.respostaAquisicaoMaxUs),
      static_cast<long long>(s.respostaControleMaxUs),
      static_cast<long long>(s.respostaAtuacaoMaxUs),
      static_cast<long long>(s.respostaSupervisaoMaxUs),
      static_cast<long long>(s.respostaFimAFimMaxUs), s.ciclosCarga,
      static_cast<unsigned long long>(s.orcamentoCargaTotalUs),
      static_cast<long long>(s.janelaCargaMaxUs));
}

void iniciarEnsaio(uint32_t duracaoS) {
  if (!hardwareOk) {
    imprimirSerial("ERRO,HARDWARE_NAO_CONFIGURADO");
    return;
  }
  if (executando()) {
    imprimirSerial("ACK,START,JA_EXECUTANDO");
    return;
  }
  if (segurancaEstaLatched()) {
    imprimirSerial("ERRO,SEGURANCA_LATCHED,ENVIE_ARM_E_ARM_HB");
    return;
  }
  if (!heartbeatEstaAtivo()) {
    imprimirSerial("ERRO,HEARTBEAT_NAO_ATIVO");
    return;
  }
  xQueueReset(filaAmostras);
  xQueueReset(filaComandos);
  xQueueReset(filaDados);
  zerarContadores();
  zerarResumosCarga();
  controle.reset();
  const int64_t agoraUs = esp_timer_get_time();
  definirJanelaEnsaio(agoraUs, agoraUs + static_cast<int64_t>(duracaoS) * 1000000);
  xEventGroupSetBits(estadoSistema, kBitExecutando);
  enfileirarMensagem("EVENT,START,%u", duracaoS);
  imprimirSerial("ACK,START,%u", duracaoS);
  xTaskNotifyGive(tarefaAquisicao);
}

void solicitarStop() {
  EventoSistema evento{TipoEvento::Stop, sequenciaStop++, esp_timer_get_time()};
  if (xQueueSend(filaEventos, &evento, 0) != pdTRUE) {
    incrementar(&contadores.eventoDescartado);
    imprimirSerial("ERRO,FILA_EVENTOS_CHEIA");
    return;
  }
  imprimirSerial("ACK,STOP");
}

void solicitarArmamento() {
  if (executando()) {
    imprimirSerial("ERRO,ARM_REQUER_SISTEMA_PARADO");
    return;
  }
  armarEmergencia();
  armarEncerramento();
  imprimirSerial("ACK,ARM");
}

void solicitarArmamentoHeartbeat() {
  if (executando()) {
    imprimirSerial("ERRO,ARM_HB_REQUER_SISTEMA_PARADO");
    return;
  }
  armarHeartbeat();
  imprimirSerial("ACK,ARM_HB");
}

void receberHeartbeat() {
  const int64_t inicioUs = esp_timer_get_time();
  if (!renovarHeartbeat(inicioUs)) {
    imprimirSerial("ERRO,HEARTBEAT_NAO_ARMADO");
    return;
  }
  const int64_t terminoUs = esp_timer_get_time();
  registrarTrace("HB_RX", sequenciaHeartbeatRecebido++, inicioUs, inicioUs,
                 terminoUs, kDeadlineDeteccaoHeartbeatUs);
  imprimirSerial("ACK,HEARTBEAT");
}

void tarefaDeComunicacao(void*) {
  for (;;) {
    if (Serial.available() <= 0) {
      vTaskDelay(pdMS_TO_TICKS(5));
      continue;
    }
    String linha = Serial.readStringUntil('\n');
    linha.trim();
    if (linha == "PING") {
      imprimirSerial("ACK,PONG,E5_CPU_LOAD");
    } else if (linha == "START") {
      iniciarEnsaio(kDuracaoPadraoS);
    } else if (linha.startsWith("START,")) {
      const uint32_t duracaoS = linha.substring(6).toInt();
      if (duracaoS < kDuracaoMinimaS || duracaoS > kDuracaoMaximaS) {
        imprimirSerial("ERRO,DURACAO_INVALIDA");
      } else {
        iniciarEnsaio(duracaoS);
      }
    } else if (linha == "STOP") {
      solicitarStop();
    } else if (linha == "ARM") {
      solicitarArmamento();
    } else if (linha == "ARM_HB") {
      solicitarArmamentoHeartbeat();
    } else if (linha == "HEARTBEAT") {
      receberHeartbeat();
    } else if (linha == "STATUS") {
      imprimirStatus();
    } else if (linha.startsWith("SUMMARY,")) {
      const uint32_t fase = linha.substring(8).toInt();
      if (fase >= kQuantidadeFasesCarga) {
        imprimirSerial("ERRO,FASE_INVALIDA");
      } else {
        imprimirResumoCarga(static_cast<uint8_t>(fase));
      }
    } else {
      imprimirSerial("ERRO,COMANDO_DESCONHECIDO,%s", linha.c_str());
    }
  }
}

void tarefaDeTelemetria(void*) {
  RegistroTrace r{};
  RegistroDados d{};
  Mensagem mensagem{};
  for (;;) {
    bool enviou = false;
    while (xQueueReceive(filaMensagens, &mensagem, 0) == pdTRUE) {
      imprimirSerial("%s", mensagem.texto);
      enviou = true;
    }
    while (xQueueReceive(filaDados, &d, 0) == pdTRUE) {
      imprimirSerial(
          "DATA,%u,%.6f,%.6f,%.6f,%.6f,%u,%u,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%lld,%lld,%lld,%lld",
          d.sequencia, d.tempoS, d.referencia, d.tpC, d.taC, d.cooler,
          d.modoCooler, d.beta, d.uNominal, d.uCooler, d.uLivre,
          d.uSaturado, d.eSenoNominal, d.eSenoCooler, d.inovacaoNominal,
          d.inovacaoCooler, static_cast<long long>(d.liberacaoUs),
          static_cast<long long>(d.aquisicaoFimUs),
          static_cast<long long>(d.controleFimUs),
          static_cast<long long>(d.atuacaoUs));
      enviou = true;
    }
    while (xQueueReceive(filaTrace, &r, 0) == pdTRUE) {
      imprimirSerial(
          "TRACE,%s,%u,%lld,%lld,%lld,%lld,%lld,%lld,%lld,%u,%lld,%lld,%u,%lld,%u,%u",
          r.tarefa, r.sequencia, static_cast<long long>(r.liberacaoUs),
          static_cast<long long>(r.inicioUs),
          static_cast<long long>(r.terminoUs),
          static_cast<long long>(r.deadlineUs),
          static_cast<long long>(r.jitterUs),
          static_cast<long long>(r.execucaoUs),
          static_cast<long long>(r.respostaUs), r.perdeuDeadline,
          static_cast<long long>(r.respostaFimAFimUs),
          static_cast<long long>(r.deadlineFimAFimUs),
          r.perdeuDeadlineFimAFim, static_cast<long long>(r.bloqueioUs),
          r.ocupacaoFilaTrace, r.descartesTrace);
      enviou = true;
    }
    if (!enviou) vTaskDelay(pdMS_TO_TICKS(5));
  }
}

void tarefaDeCarga(void*) {
  uint8_t faseAnterior = 0xFF;
  TickType_t ultimaLiberacao = xTaskGetTickCount();
  const TickType_t periodo = pdMS_TO_TICKS(kPeriodoCargaUs / 1000U);

  for (;;) {
    if (!executando()) {
      faseAnterior = 0xFF;
      vTaskDelay(pdMS_TO_TICKS(10));
      ultimaLiberacao = xTaskGetTickCount();
      continue;
    }

    const int64_t inicioJanelaUs = esp_timer_get_time();
    uint8_t fase = 0;
    if (!obterFaseCarga(inicioJanelaUs, &fase)) {
      vTaskDelay(pdMS_TO_TICKS(1));
      continue;
    }
    if (fase != faseAnterior) {
      enfileirarMensagem("EVENT,CARGA,FASE,%u,PCT,%u", fase,
                         kCargasPercentuais[fase]);
      faseAnterior = fase;
    }

    const uint32_t orcamentoUs =
        kPeriodoCargaUs * kCargasPercentuais[fase] / 100U;
    while (executando() &&
           esp_timer_get_time() - inicioJanelaUs < orcamentoUs) {
      acumuladorCarga = acumuladorCarga * 1664525U + 1013904223U;
    }
    const int64_t fimJanelaUs = esp_timer_get_time();
    registrarCicloCarga(fase, orcamentoUs, fimJanelaUs - inicioJanelaUs);
    vTaskDelayUntil(&ultimaLiberacao, periodo);
  }
}

void criarTarefa(TaskFunction_t funcao, const char* nome, uint32_t pilha,
                 UBaseType_t prioridade, TaskHandle_t* handle,
                 BaseType_t nucleo) {
  const BaseType_t ok = xTaskCreatePinnedToCore(
      funcao, nome, pilha, nullptr, prioridade, handle, nucleo);
  configASSERT(ok == pdPASS);
}

}  // namespace

void setup() {
  digitalWrite(kPinAquecedor, LOW);
  digitalWrite(kPinCooler, LOW);
  pinMode(kPinAquecedor, OUTPUT);
  pinMode(kPinCooler, OUTPUT);

  Serial.begin(115200);
  Serial.setTimeout(20);
  delay(300);

  filaAmostras = xQueueCreate(1, sizeof(Amostra));
  filaComandos = xQueueCreate(2, sizeof(ComandoAtuacao));
  filaEventos = xQueueCreate(8, sizeof(EventoSistema));
  filaTrace = xQueueCreate(128, sizeof(RegistroTrace));
  filaDados = xQueueCreate(16, sizeof(RegistroDados));
  filaMensagens = xQueueCreate(16, sizeof(Mensagem));
  mutexAdc = xSemaphoreCreateMutex();
  mutexSerial = xSemaphoreCreateMutex();
  estadoSistema = xEventGroupCreate();
  configASSERT(filaAmostras && filaComandos && filaEventos && filaTrace &&
               filaDados && filaMensagens && mutexAdc && mutexSerial &&
               estadoSistema);

  const uint32_t fa = ledcSetup(kCanalAquecedor, 1000, 16);
  const uint32_t fc = ledcSetup(kCanalCooler, 5000, 12);
  if (fa > 0 && fc > 0) {
    ledcAttachPin(kPinAquecedor, kCanalAquecedor);
    ledcAttachPin(kPinCooler, kCanalCooler);
    escreverPwm(0, 0);
    hardwareOk = ledcRead(kCanalAquecedor) == 0 &&
                 ledcRead(kCanalCooler) == 0;
  }

  analogReadResolution(12);
  analogSetPinAttenuation(kPinTp, ADC_0db);
  analogSetPinAttenuation(kPinTa, ADC_0db);

  criarTarefa(tarefaDeAtuacao, "T_Atuacao", 6144, 8, &tarefaAtuacao, 1);
  criarTarefa(tarefaDeWatchdogComunicacao, "T_Watchdog", 4096, 7, nullptr, 1);
  criarTarefa(tarefaDeSupervisao, "T_Supervisao", 4096, 6, nullptr, 1);
  criarTarefa(tarefaDeControle, "T_Controle", 6144, 5, nullptr, 1);
  criarTarefa(tarefaDeAquisicao, "T_Aquisicao", 4096, 4,
               &tarefaAquisicao, 1);
  criarTarefa(tarefaDeComunicacao, "T_Comunicacao", 4096, 3, nullptr, 0);
  criarTarefa(tarefaDeTelemetria, "T_Telemetria", 7168, 2, nullptr, 0);
  criarTarefa(tarefaDeCarga, "T_Carga", 4096, 1, nullptr, 1);

  pinMode(kPinoEmergencia, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(kPinoEmergencia), isrEmergencia,
                  FALLING);

  imprimirSerial(
      "READY,E5_CPU_LOAD,TS_MS,%u,DURACAO_S,%u,TP_GPIO,%u,TA_GPIO,%u,HEAT_GPIO,%u,COOL_GPIO,%u,LOADS,0-10-25-40-60",
      kPeriodoControleMs, kDuracaoPadraoS, kPinTp, kPinTa,
      kPinAquecedor, kPinCooler);
  imprimirSerial(
      "TRACE_HEADER,task,seq,release_us,start_us,finish_us,deadline_us,jitter_us,exec_us,response_us,miss,e2e_us,e2e_deadline_us,e2e_miss,block_us,q_trace,drops");
  imprimirSerial(
      "DATA_HEADER,seq,t_s,R,Tp,Ta,W,modo,beta,U_nom,U_cool,U_livre,Us,e_sin_nom,e_sin_cool,inov_nom,inov_cool,release_us,acq_finish_us,control_finish_us,actuate_us");
  if (!hardwareOk) imprimirSerial("EVENT,ALARM,CONFIG_PWM");
}

void loop() { vTaskDelete(nullptr); }
