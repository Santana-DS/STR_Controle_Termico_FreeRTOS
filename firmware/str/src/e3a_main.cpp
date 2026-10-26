#include <Arduino.h>

#include <math.h>
#include <stdarg.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#if !defined(STR_E3A_IO_PREFLIGHT)
#error "Este arquivo pertence exclusivamente ao preflight passivo E3a."
#endif

namespace {

constexpr uint8_t kPinTp = 36;
constexpr uint8_t kPinTa = 34;
constexpr uint8_t kPinAquecedor = 25;
constexpr uint8_t kPinCooler = 26;
constexpr uint8_t kCanalAquecedor = 0;
constexpr uint8_t kCanalCooler = 2;
constexpr uint16_t kConversoesAdc = 128;
constexpr uint32_t kPeriodoAquisicaoMs = 1000;
constexpr int64_t kPeriodoAquisicaoUs = 1000000;
constexpr int64_t kDeadlineAquisicaoUs = 600000;
constexpr uint32_t kAmostrasPadrao = 30;

SemaphoreHandle_t mutexAdc = nullptr;
SemaphoreHandle_t mutexSerial = nullptr;
TaskHandle_t tarefaAquisicao = nullptr;

portMUX_TYPE muxEstado = portMUX_INITIALIZER_UNLOCKED;
volatile bool executando = false;
volatile bool configuracaoHardwareOk = false;
volatile uint32_t amostrasSolicitadas = kAmostrasPadrao;

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

void escreverSaidaSegura() {
  ledcWrite(kCanalAquecedor, 0);
  ledcWrite(kCanalCooler, 0);
}

bool saidasEstaoEmZero() {
  return ledcRead(kCanalAquecedor) == 0 && ledcRead(kCanalCooler) == 0;
}

bool estaExecutando() {
  portENTER_CRITICAL(&muxEstado);
  const bool valor = executando;
  portEXIT_CRITICAL(&muxEstado);
  return valor;
}

void definirExecutando(bool valor) {
  portENTER_CRITICAL(&muxEstado);
  executando = valor;
  portEXIT_CRITICAL(&muxEstado);
}

double lerTemperatura(uint8_t pino) {
  double somaMv = 0.0;
  for (uint16_t i = 0; i < kConversoesAdc; ++i) {
    somaMv += analogReadMilliVolts(pino);
    delayMicroseconds(1000);
  }
  return somaMv / (10.0 * kConversoesAdc);
}

void tarefaDeAquisicao(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    TickType_t ultimaLiberacao = xTaskGetTickCount();
    int64_t liberacaoEsperadaUs = esp_timer_get_time();

    for (uint32_t sequencia = 0;
         sequencia < amostrasSolicitadas && estaExecutando(); ++sequencia) {
      escreverSaidaSegura();
      const int64_t inicioUs = esp_timer_get_time();
      double tpC = NAN;
      double taC = NAN;
      int64_t esperaAdcUs = 0;

      const int64_t pedidoAdcUs = esp_timer_get_time();
      if (xSemaphoreTake(mutexAdc, pdMS_TO_TICKS(550)) == pdTRUE) {
        const int64_t posseAdcUs = esp_timer_get_time();
        esperaAdcUs = posseAdcUs - pedidoAdcUs;
        tpC = lerTemperatura(kPinTp);
        taC = lerTemperatura(kPinTa);
        xSemaphoreGive(mutexAdc);
      }

      escreverSaidaSegura();
      const uint32_t pwmAquecedor = ledcRead(kCanalAquecedor);
      const uint32_t pwmCooler = ledcRead(kCanalCooler);
      const int64_t terminoUs = esp_timer_get_time();
      const int64_t liberacaoMedidaUs =
          inicioUs < liberacaoEsperadaUs ? inicioUs : liberacaoEsperadaUs;
      const int64_t jitterUs = inicioUs - liberacaoMedidaUs;
      const int64_t execucaoUs = terminoUs - inicioUs;
      const int64_t respostaUs = terminoUs - liberacaoMedidaUs;
      const bool perdeuDeadline = respostaUs > kDeadlineAquisicaoUs;
      const bool sensoresValidos = isfinite(tpC) && isfinite(taC) &&
          tpC >= -10.0 && tpC <= 100.0 && taC >= -10.0 && taC <= 100.0;
      const bool saidasSeguras = pwmAquecedor == 0 && pwmCooler == 0;

      imprimirSerial(
          "IO,%u,%lld,%lld,%lld,%lld,%lld,%lld,%lld,%u,%.6f,%.6f,%u,%u,%lld,%u,%u,%u",
          sequencia, static_cast<long long>(liberacaoMedidaUs),
          static_cast<long long>(inicioUs), static_cast<long long>(terminoUs),
          static_cast<long long>(kDeadlineAquisicaoUs),
          static_cast<long long>(jitterUs), static_cast<long long>(execucaoUs),
          static_cast<long long>(respostaUs), perdeuDeadline ? 1U : 0U, tpC,
          taC, pwmAquecedor, pwmCooler, static_cast<long long>(esperaAdcUs),
          sensoresValidos ? 1U : 0U, saidasSeguras ? 1U : 0U,
          static_cast<unsigned>(kConversoesAdc));

      if (!sensoresValidos || !saidasSeguras || perdeuDeadline) {
        definirExecutando(false);
        escreverSaidaSegura();
        imprimirSerial("ALARM,E3A,%s%s%s",
                       !sensoresValidos ? "SENSOR_INVALIDO" : "",
                       !saidasSeguras ? " PWM_NAO_ZERO" : "",
                       perdeuDeadline ? " DEADLINE" : "");
        break;
      }

      vTaskDelayUntil(&ultimaLiberacao,
                      pdMS_TO_TICKS(kPeriodoAquisicaoMs));
      liberacaoEsperadaUs += kPeriodoAquisicaoUs;
    }

    definirExecutando(false);
    escreverSaidaSegura();
    imprimirSerial("DONE,E3A,OUTPUTS_ZERO,%u", saidasEstaoEmZero() ? 1U : 0U);
  }
}

void iniciarPreflight(uint32_t quantidade) {
  if (!configuracaoHardwareOk) {
    imprimirSerial("ERRO,HARDWARE_NAO_CONFIGURADO");
    return;
  }
  if (estaExecutando()) {
    imprimirSerial("ACK,START_IO,JA_EXECUTANDO");
    return;
  }
  escreverSaidaSegura();
  amostrasSolicitadas = quantidade;
  definirExecutando(true);
  imprimirSerial("ACK,START_IO,%u", quantidade);
  xTaskNotifyGive(tarefaAquisicao);
}

void pararPreflight() {
  definirExecutando(false);
  escreverSaidaSegura();
  imprimirSerial("ACK,STOP");
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
      imprimirSerial("ACK,PONG,E3A_IO_PREFLIGHT");
    } else if (linha == "START_IO") {
      iniciarPreflight(kAmostrasPadrao);
    } else if (linha.startsWith("START_IO,")) {
      const uint32_t quantidade = linha.substring(9).toInt();
      if (quantidade < 1 || quantidade > 300) {
        imprimirSerial("ERRO,QUANTIDADE_INVALIDA");
      } else {
        iniciarPreflight(quantidade);
      }
    } else if (linha == "STOP") {
      pararPreflight();
    } else if (linha == "STATUS") {
      imprimirSerial("STATUS,E3A,%u,%u,%u,%u",
                     estaExecutando() ? 1U : 0U,
                     configuracaoHardwareOk ? 1U : 0U,
                     ledcRead(kCanalAquecedor), ledcRead(kCanalCooler));
    } else {
      imprimirSerial("ERRO,COMANDO_DESCONHECIDO,%s", linha.c_str());
    }
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

  mutexAdc = xSemaphoreCreateMutex();
  mutexSerial = xSemaphoreCreateMutex();
  configASSERT(mutexAdc && mutexSerial);

  const uint32_t frequenciaAquecedor =
      ledcSetup(kCanalAquecedor, 1000, 16);
  const uint32_t frequenciaCooler = ledcSetup(kCanalCooler, 5000, 12);
  if (frequenciaAquecedor > 0 && frequenciaCooler > 0) {
    ledcAttachPin(kPinAquecedor, kCanalAquecedor);
    ledcAttachPin(kPinCooler, kCanalCooler);
    escreverSaidaSegura();
    configuracaoHardwareOk = saidasEstaoEmZero();
  }

  analogReadResolution(12);
  analogSetPinAttenuation(kPinTp, ADC_0db);
  analogSetPinAttenuation(kPinTa, ADC_0db);

  criarTarefa(tarefaDeAquisicao, "T_AquisicaoIO", 4096, 5,
               &tarefaAquisicao, 1);
  criarTarefa(tarefaDeComunicacao, "T_Comunicacao", 4096, 3, nullptr, 0);

  imprimirSerial(
      "READY,E3A_IO_PREFLIGHT,TP_GPIO,%u,TA_GPIO,%u,HEAT_GPIO,%u,COOL_GPIO,%u,SEM_12V",
      kPinTp, kPinTa, kPinAquecedor, kPinCooler);
  imprimirSerial(
      "HEADER,seq,release_us,start_us,finish_us,deadline_us,jitter_us,exec_us,response_us,miss,Tp_C,Ta_C,pwm_heat,pwm_cool,adc_wait_us,sensors_ok,outputs_zero,n_adc");
  if (!configuracaoHardwareOk) {
    imprimirSerial("ALARM,E3A,CONFIG_PWM");
  }
}

void loop() {
  escreverSaidaSegura();
  vTaskDelay(pdMS_TO_TICKS(100));
}
