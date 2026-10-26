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

#if !defined(STR_E7_HEARTBEAT)
#error "Este arquivo pertence exclusivamente ao runner de heartbeat E7."
#endif

namespace {

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
constexpr uint32_t kPeriodoWatchdogMs = 5;
constexpr int64_t kDeadlineDeteccaoHeartbeatUs = 20000;
constexpr int64_t kDeadlineHeartbeatUs = 50000;
constexpr uint8_t kPinoEmergencia = 0;
constexpr int64_t kDebounceEmergenciaUs = 200000;

constexpr EventBits_t kBitExecutando = BIT0;

struct Amostra {
  uint32_t sequencia;
  double tempoS;
  double temperaturaC;
  int64_t liberacaoAquisicaoUs;
  int64_t terminoAquisicaoUs;
};

struct ComandoAtuacao {
  uint32_t sequencia;
  uint16_t aquecedor;
  uint16_t cooler;
  bool seguro;
  int64_t liberacaoLocalUs;
  int64_t origemFimAFimUs;
  int64_t deadlineFimAFimUs;
};

enum class TipoEvento : uint8_t { Stop = 1 };

struct EventoSistema {
  TipoEvento tipo;
  uint32_t sequencia;
  int64_t instanteUs;
};

struct RegistroTrace {
  char tarefa[12];
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
  uint16_t ocupacaoFilaTrace;
  uint32_t descartesTrace;
};

struct Contadores {
  uint32_t traceDescartado;
  uint32_t amostraDescartada;
  uint32_t comandoDescartado;
  uint32_t eventoDescartado;
};

QueueHandle_t filaAmostras = nullptr;
QueueHandle_t filaComandos = nullptr;
QueueHandle_t filaEventos = nullptr;
QueueHandle_t filaTrace = nullptr;
SemaphoreHandle_t mutexSerial = nullptr;
EventGroupHandle_t estadoSistema = nullptr;
TaskHandle_t tarefaAquisicao = nullptr;
TaskHandle_t tarefaAtuacao = nullptr;

portMUX_TYPE muxContadores = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE muxEmergencia = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE muxHeartbeat = portMUX_INITIALIZER_UNLOCKED;
Contadores contadores{};
uint32_t sequenciaStop = 0;
uint32_t sequenciaEmergencia = 0;
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
uint32_t sequenciaHeartbeat = 0;
uint32_t sequenciaHeartbeatRecebido = 0;
strcontrol::ControlCore controle;

bool executando() {
  return (xEventGroupGetBits(estadoSistema) & kBitExecutando) != 0;
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

void imprimirSerial(const char* formato, ...) {
  char linha[384];
  va_list argumentos;
  va_start(argumentos, formato);
  vsnprintf(linha, sizeof(linha), formato, argumentos);
  va_end(argumentos);

  if (xSemaphoreTake(mutexSerial, pdMS_TO_TICKS(100)) == pdTRUE) {
    Serial.println(linha);
    xSemaphoreGive(mutexSerial);
  }
}

void registrarTrace(const char* tarefa, uint32_t sequencia,
                    int64_t liberacaoUs, int64_t inicioUs, int64_t terminoUs,
                    int64_t deadlineUs, int64_t origemFimAFimUs = -1,
                    int64_t deadlineFimAFimUs = 0) {
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
  r.ocupacaoFilaTrace = uxQueueMessagesWaiting(filaTrace);
  r.descartesTrace = copiarContadores().traceDescartado;

  if (xQueueSend(filaTrace, &r, 0) != pdTRUE) {
    incrementar(&contadores.traceDescartado);
  }
}

void tarefaDeAquisicao(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    TickType_t ultimaLiberacao = xTaskGetTickCount();
    int64_t liberacaoEsperadaUs = esp_timer_get_time();
    uint32_t sequencia = 0;

    while (executando()) {
      const int64_t inicioUs = esp_timer_get_time();
      Amostra amostra{};
      amostra.sequencia = sequencia;
      amostra.tempoS = static_cast<double>(sequencia) * 5.715;
      amostra.temperaturaC =
          50.0 + 2.0 * sin(2.0 * PI * amostra.tempoS / 180.0);
      amostra.liberacaoAquisicaoUs = liberacaoEsperadaUs;
      amostra.terminoAquisicaoUs = esp_timer_get_time();

      if (xQueueSend(filaAmostras, &amostra, 0) != pdTRUE) {
        incrementar(&contadores.amostraDescartada);
      }
      registrarTrace("AQUISICAO", sequencia, liberacaoEsperadaUs, inicioUs,
                     amostra.terminoAquisicaoUs, kDeadlineAquisicaoUs);

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

    const int64_t inicioUs = esp_timer_get_time();
    if (amostra.sequencia == 0) controle.reset();
    const strcontrol::SaidaControle saida = controle.step(
        static_cast<uint16_t>(amostra.sequencia), amostra.tempoS,
        amostra.temperaturaC);
    const int64_t terminoUs = esp_timer_get_time();

    ComandoAtuacao comando{};
    comando.sequencia = amostra.sequencia;
    comando.aquecedor = static_cast<uint16_t>(saida.uSaturado);
    comando.cooler = saida.cooler;
    comando.seguro = false;
    comando.liberacaoLocalUs = terminoUs;
    comando.origemFimAFimUs = amostra.liberacaoAquisicaoUs;
    comando.deadlineFimAFimUs = kDeadlineFimAFimUs;
    if (xQueueSend(filaComandos, &comando, 0) != pdTRUE) {
      incrementar(&contadores.comandoDescartado);
    } else {
      xTaskNotifyGive(tarefaAtuacao);
    }

    registrarTrace("CONTROLE", amostra.sequencia,
                   amostra.terminoAquisicaoUs, inicioUs, terminoUs,
                   kDeadlineControleUs, amostra.liberacaoAquisicaoUs,
                   kDeadlineFimAFimUs);
  }
}

bool emergenciaEstaLatched() {
  portENTER_CRITICAL(&muxEmergencia);
  const bool ativa = emergenciaLatched;
  portEXIT_CRITICAL(&muxEmergencia);
  return ativa;
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

void armarEmergencia() {
  portENTER_CRITICAL(&muxEmergencia);
  emergenciaPendente = false;
  emergenciaLatched = false;
  emergenciaArmada = true;
  ultimoPulsoEmergenciaUs = 0;
  portEXIT_CRITICAL(&muxEmergencia);
}

bool heartbeatEstaAtivo() {
  portENTER_CRITICAL(&muxHeartbeat);
  const bool ativo = heartbeatAtivo;
  portEXIT_CRITICAL(&muxHeartbeat);
  return ativo;
}

bool heartbeatEstaLatched() {
  portENTER_CRITICAL(&muxHeartbeat);
  const bool latched = heartbeatLatched;
  portEXIT_CRITICAL(&muxHeartbeat);
  return latched;
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
      registrarTrace("DET_HB", sequencia, vencimentoUs, inicioUs, terminoUs,
                     kDeadlineDeteccaoHeartbeatUs, vencimentoUs,
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

void tarefaDeAtuacao(void*) {
  ComandoAtuacao comando{};
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

    int64_t instanteEventoUs = 0;
    uint32_t sequenciaEvento = 0;
    if (consumirEmergencia(&instanteEventoUs, &sequenciaEvento)) {
      const int64_t inicioUs = esp_timer_get_time();
      xEventGroupClearBits(estadoSistema, kBitExecutando);
      volatile uint16_t sumidouroSeguro = 0;
      (void)sumidouroSeguro;
      const int64_t terminoUs = esp_timer_get_time();
      xQueueReset(filaComandos);
      registrarTrace("ATUA_EMERG", sequenciaEvento, instanteEventoUs,
                     inicioUs, terminoUs, kDeadlineEmergenciaUs,
                     instanteEventoUs, kDeadlineEmergenciaUs);
    }

    int64_t vencimentoHeartbeat = 0;
    int64_t deteccaoHeartbeat = 0;
    uint32_t sequenciaFalhaHeartbeat = 0;
    if (consumirFalhaHeartbeat(&vencimentoHeartbeat, &deteccaoHeartbeat,
                               &sequenciaFalhaHeartbeat)) {
      const int64_t inicioUs = esp_timer_get_time();
      xEventGroupClearBits(estadoSistema, kBitExecutando);
      volatile uint16_t sumidouroSeguro = 0;
      (void)sumidouroSeguro;
      const int64_t terminoUs = esp_timer_get_time();
      xQueueReset(filaComandos);
      registrarTrace("ATUA_HB", sequenciaFalhaHeartbeat,
                     deteccaoHeartbeat, inicioUs, terminoUs,
                     kDeadlineAtuacaoUs, vencimentoHeartbeat,
                     kDeadlineHeartbeatUs);
    }

    while (xQueueReceive(filaComandos, &comando, 0) == pdTRUE) {
      const int64_t inicioUs = esp_timer_get_time();

      // E2 permanece seguro: os valores sao consumidos, mas nenhum canal PWM
      // e configurado ou escrito. Um latch ativo impede comando normal.
      const bool aplicarSeguro = comando.seguro || emergenciaEstaLatched();
      volatile uint16_t sumidouro =
          aplicarSeguro
              ? 0
              : static_cast<uint16_t>(comando.aquecedor + comando.cooler);
      (void)sumidouro;
      const int64_t terminoUs = esp_timer_get_time();
      if (comando.seguro) {
        registrarTrace("ATUA_STOP", comando.sequencia,
                       comando.liberacaoLocalUs, inicioUs, terminoUs,
                       kDeadlineAtuacaoUs, comando.origemFimAFimUs,
                       comando.deadlineFimAFimUs);
      } else if (!aplicarSeguro) {
        registrarTrace("ATUACAO", comando.sequencia,
                       comando.liberacaoLocalUs, inicioUs, terminoUs,
                       kDeadlineAtuacaoUs, comando.origemFimAFimUs,
                       comando.deadlineFimAFimUs);
      }
    }
  }
}

void tratarStop(const EventoSistema& evento) {
  const int64_t inicioUs = esp_timer_get_time();
  xEventGroupClearBits(estadoSistema, kBitExecutando);
  const int64_t terminoUs = esp_timer_get_time();

  ComandoAtuacao seguro{};
  seguro.sequencia = evento.sequencia;
  seguro.seguro = true;
  seguro.liberacaoLocalUs = terminoUs;
  seguro.origemFimAFimUs = evento.instanteUs;
  seguro.deadlineFimAFimUs = kDeadlineStopUs;
  if (xQueueSendToFront(filaComandos, &seguro, 0) != pdTRUE) {
    incrementar(&contadores.comandoDescartado);
  } else {
    xTaskNotifyGive(tarefaAtuacao);
  }

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
      // O tick do FreeRTOS e o esp_timer nao compartilham a mesma origem.
      // O primeiro job observado ancora as liberacoes seguintes no relogio
      // de instrumentacao, evitando um deslocamento constante artificial.
      liberacaoEsperadaUs = inicioUs;
      referenciaTemporalDefinida = true;
    }
    const int64_t liberacaoParaTrace =
        inicioUs < liberacaoEsperadaUs ? inicioUs : liberacaoEsperadaUs;
    const bool sistemaExecutando = executando();
    (void)sistemaExecutando;
    const int64_t terminoUs = esp_timer_get_time();
    registrarTrace("SUPERVISAO", sequencia++, liberacaoParaTrace, inicioUs,
                   terminoUs, kDeadlineSupervisaoUs);
    proximaLiberacao += periodo;
    liberacaoEsperadaUs += kPeriodoSupervisaoUs;
  }
}

void imprimirStatus() {
  const Contadores c = copiarContadores();
  portENTER_CRITICAL(&muxEmergencia);
  const bool armada = emergenciaArmada;
  const bool latched = emergenciaLatched;
  portEXIT_CRITICAL(&muxEmergencia);
  imprimirSerial("STATUS,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u",
                 executando() ? 1U : 0U,
                 armada ? 1U : 0U, latched ? 1U : 0U,
                 static_cast<unsigned>(uxQueueMessagesWaiting(filaAmostras)),
                 static_cast<unsigned>(uxQueueMessagesWaiting(filaComandos)),
                 static_cast<unsigned>(uxQueueMessagesWaiting(filaTrace)),
                 c.traceDescartado, c.amostraDescartada, c.comandoDescartado,
                 c.eventoDescartado);
}

void iniciarEnsaio() {
  if (executando()) {
    imprimirSerial("ACK,START,JA_EXECUTANDO");
    return;
  }
  if (emergenciaEstaLatched()) {
    imprimirSerial("ERRO,EMERGENCIA_LATCHED,ENVIE_ARM");
    return;
  }
  if (heartbeatEstaLatched()) {
    imprimirSerial("ERRO,HEARTBEAT_LATCHED,ENVIE_ARM_HB");
    return;
  }
  if (!heartbeatEstaAtivo()) {
    imprimirSerial("ERRO,HEARTBEAT_NAO_ATIVO");
    return;
  }
  xQueueReset(filaAmostras);
  xQueueReset(filaComandos);
  zerarContadores();
  xEventGroupSetBits(estadoSistema, kBitExecutando);
  imprimirSerial("ACK,START");
  xTaskNotifyGive(tarefaAquisicao);
}

void solicitarStop() {
  EventoSistema evento{};
  evento.tipo = TipoEvento::Stop;
  evento.sequencia = sequenciaStop++;
  evento.instanteUs = esp_timer_get_time();
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
      imprimirSerial("ACK,PONG,E7_HEARTBEAT");
    } else if (linha == "START") {
      iniciarEnsaio();
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
    } else {
      imprimirSerial("ERRO,COMANDO_DESCONHECIDO,%s", linha.c_str());
    }
  }
}

void tarefaDeTelemetria(void*) {
  RegistroTrace r{};
  for (;;) {
    if (xQueueReceive(filaTrace, &r, portMAX_DELAY) != pdTRUE) continue;
    imprimirSerial(
        "TRACE,%s,%u,%lld,%lld,%lld,%lld,%lld,%lld,%lld,%u,%lld,%lld,%u,%u,%u",
        r.tarefa, r.sequencia, static_cast<long long>(r.liberacaoUs),
        static_cast<long long>(r.inicioUs),
        static_cast<long long>(r.terminoUs),
        static_cast<long long>(r.deadlineUs),
        static_cast<long long>(r.jitterUs),
        static_cast<long long>(r.execucaoUs),
        static_cast<long long>(r.respostaUs), r.perdeuDeadline,
        static_cast<long long>(r.respostaFimAFimUs),
        static_cast<long long>(r.deadlineFimAFimUs),
        r.perdeuDeadlineFimAFim, r.ocupacaoFilaTrace, r.descartesTrace);
  }
}

void criarTarefa(TaskFunction_t funcao, const char* nome, uint32_t pilha,
                 UBaseType_t prioridade, TaskHandle_t* handle, BaseType_t nucleo) {
  const BaseType_t ok = xTaskCreatePinnedToCore(funcao, nome, pilha, nullptr,
                                                prioridade, handle, nucleo);
  configASSERT(ok == pdPASS);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(20);
  delay(300);

  filaAmostras = xQueueCreate(1, sizeof(Amostra));
  filaComandos = xQueueCreate(2, sizeof(ComandoAtuacao));
  filaEventos = xQueueCreate(8, sizeof(EventoSistema));
  filaTrace = xQueueCreate(128, sizeof(RegistroTrace));
  mutexSerial = xSemaphoreCreateMutex();
  estadoSistema = xEventGroupCreate();
  configASSERT(filaAmostras && filaComandos && filaEventos && filaTrace &&
               mutexSerial && estadoSistema);

  criarTarefa(tarefaDeAtuacao, "T_Atuacao", 4096, 8, &tarefaAtuacao, 1);
  criarTarefa(tarefaDeWatchdogComunicacao, "T_Watchdog", 4096, 7, nullptr,
               1);
  criarTarefa(tarefaDeSupervisao, "T_Supervisao", 4096, 6, nullptr, 1);
  criarTarefa(tarefaDeControle, "T_Controle", 6144, 5, nullptr, 1);
  criarTarefa(tarefaDeAquisicao, "T_Aquisicao", 4096, 4,
               &tarefaAquisicao, 1);
  criarTarefa(tarefaDeComunicacao, "T_Comunicacao", 4096, 3, nullptr, 0);
  criarTarefa(tarefaDeTelemetria, "T_Telemetria", 6144, 2, nullptr, 0);

  pinMode(kPinoEmergencia, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(kPinoEmergencia), isrEmergencia,
                  FALLING);

  imprimirSerial(
      "READY,E7_HEARTBEAT,TIMEOUT_MS,%lld,SEM_ADC,SEM_PWM,TS_MS,%u",
      static_cast<long long>(kTimeoutHeartbeatUs / 1000),
      kPeriodoControleMs);
  imprimirSerial(
      "HEADER,task,seq,release_us,start_us,finish_us,deadline_us,jitter_us,exec_us,response_us,miss,e2e_us,e2e_deadline_us,e2e_miss,q_trace,drops");
}

void loop() { vTaskDelete(nullptr); }
