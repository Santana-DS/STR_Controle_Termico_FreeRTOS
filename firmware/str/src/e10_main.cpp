#include <Arduino.h>

#include <math.h>
#include <stdarg.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#if !defined(STR_E10_PRIORITY_INVERSION)
#error "Compile este arquivo somente no ambiente e10_priority_inversion."
#endif

namespace {

constexpr uint8_t kPinAquecedor = 25;
constexpr uint8_t kPinCooler = 26;
constexpr uint32_t kRepeticoes = 30;
constexpr uint32_t kTrabalhoBaixaUs = 20000;
constexpr uint32_t kTrabalhoMediaUs = 50000;
constexpr EventBits_t kBitBaixaPossui = BIT0;
constexpr EventBits_t kBitAltaSolicitou = BIT1;
constexpr EventBits_t kBitLiberarBaixa = BIT2;
constexpr EventBits_t kBitAltaConcluiu = BIT3;
constexpr EventBits_t kBitMediaConcluiu = BIT4;

enum class Cenario : uint8_t {
  MutexBaseline = 0,
  MutexHeranca = 1,
  BinarioInversao = 2
};

struct Resultado {
  Cenario cenario;
  uint32_t repeticao;
  int64_t esperaAltaUs;
  int64_t janelaBaixaUs;
  int64_t janelaMediaUs;
  UBaseType_t prioridadeEfetivaBaixa;
};

SemaphoreHandle_t mutexRecurso = nullptr;
SemaphoreHandle_t binarioRecurso = nullptr;
SemaphoreHandle_t mutexSerial = nullptr;
EventGroupHandle_t eventos = nullptr;
TaskHandle_t tarefaBaixaHandle = nullptr;
TaskHandle_t tarefaMediaHandle = nullptr;
TaskHandle_t tarefaAltaHandle = nullptr;
TaskHandle_t tarefaEnsaioHandle = nullptr;

volatile uint32_t acumulador = 0x2468ACE1U;
volatile Cenario cenarioAtual = Cenario::MutexBaseline;
volatile int64_t esperaAltaUs = 0;
volatile int64_t janelaBaixaUs = 0;
volatile int64_t janelaMediaUs = 0;
volatile UBaseType_t prioridadeEfetivaBaixa = 0;
volatile bool executando = false;
double iteracoesPorUs = 0.0;

void imprimir(const char* formato, ...) {
  char linha[256];
  va_list args;
  va_start(args, formato);
  vsnprintf(linha, sizeof(linha), formato, args);
  va_end(args);
  if (xSemaphoreTake(mutexSerial, pdMS_TO_TICKS(250)) == pdTRUE) {
    Serial.println(linha);
    xSemaphoreGive(mutexSerial);
  }
}

void executarTrabalho(uint32_t duracaoAlvoUs) {
  const uint32_t iteracoes = static_cast<uint32_t>(
      llround(iteracoesPorUs * static_cast<double>(duracaoAlvoUs)));
  for (uint32_t i = 0; i < iteracoes; ++i)
    acumulador = acumulador * 1664525U + 1013904223U;
}

double calibrarTrabalho() {
  uint32_t iteracoes = 500000;
  for (uint8_t tentativa = 0; tentativa < 3; ++tentativa) {
    const int64_t inicioUs = esp_timer_get_time();
    for (uint32_t i = 0; i < iteracoes; ++i)
      acumulador = acumulador * 1664525U + 1013904223U;
    const int64_t duracaoUs = esp_timer_get_time() - inicioUs;
    if (duracaoUs >= 5000) break;
    const int64_t seguroUs = duracaoUs > 0 ? duracaoUs : 1;
    iteracoes *= static_cast<uint32_t>(5000 / seguroUs) + 1U;
  }

  double taxas[5]{};
  for (uint8_t k = 0; k < 5; ++k) {
    const int64_t inicioUs = esp_timer_get_time();
    for (uint32_t i = 0; i < iteracoes; ++i)
      acumulador = acumulador * 1664525U + 1013904223U;
    const int64_t medidoUs = esp_timer_get_time() - inicioUs;
    taxas[k] = static_cast<double>(iteracoes) /
               static_cast<double>(medidoUs > 0 ? medidoUs : 1);
  }
  for (uint8_t i = 1; i < 5; ++i) {
    const double atual = taxas[i];
    uint8_t j = i;
    while (j > 0 && taxas[j - 1] > atual) {
      taxas[j] = taxas[j - 1];
      --j;
    }
    taxas[j] = atual;
  }
  return taxas[2];
}

SemaphoreHandle_t recursoAtual() {
  return cenarioAtual == Cenario::BinarioInversao ? binarioRecurso
                                                   : mutexRecurso;
}

const char* nomeCenario(Cenario cenario) {
  switch (cenario) {
    case Cenario::MutexBaseline: return "MUTEX_BASELINE";
    case Cenario::MutexHeranca: return "MUTEX_HERANCA";
    case Cenario::BinarioInversao: return "BINARIO_INVERSAO";
    default: return "INVALIDO";
  }
}

void tarefaBaixa(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    SemaphoreHandle_t recurso = recursoAtual();
    configASSERT(xSemaphoreTake(recurso, portMAX_DELAY) == pdTRUE);
    xEventGroupSetBits(eventos, kBitBaixaPossui);
    xEventGroupWaitBits(eventos, kBitLiberarBaixa, pdFALSE, pdTRUE,
                        portMAX_DELAY);

    prioridadeEfetivaBaixa = uxTaskPriorityGet(nullptr);
    const int64_t inicioUs = esp_timer_get_time();
    executarTrabalho(kTrabalhoBaixaUs);
    janelaBaixaUs = esp_timer_get_time() - inicioUs;
    xSemaphoreGive(recurso);
  }
}

void tarefaAlta(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    SemaphoreHandle_t recurso = recursoAtual();
    const int64_t pedidoUs = esp_timer_get_time();
    xEventGroupSetBits(eventos, kBitAltaSolicitou);
    configASSERT(xSemaphoreTake(recurso, portMAX_DELAY) == pdTRUE);
    esperaAltaUs = esp_timer_get_time() - pedidoUs;
    xSemaphoreGive(recurso);
    xEventGroupSetBits(eventos, kBitAltaConcluiu);
  }
}

void tarefaMedia(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    const int64_t inicioUs = esp_timer_get_time();
    executarTrabalho(kTrabalhoMediaUs);
    janelaMediaUs = esp_timer_get_time() - inicioUs;
    xEventGroupSetBits(eventos, kBitMediaConcluiu);
  }
}

Resultado executarRepeticao(Cenario cenario, uint32_t repeticao) {
  cenarioAtual = cenario;
  esperaAltaUs = 0;
  janelaBaixaUs = 0;
  janelaMediaUs = 0;
  prioridadeEfetivaBaixa = 0;
  xEventGroupClearBits(eventos, kBitBaixaPossui | kBitAltaSolicitou |
                                   kBitLiberarBaixa | kBitAltaConcluiu |
                                   kBitMediaConcluiu);

  xTaskNotifyGive(tarefaBaixaHandle);
  configASSERT((xEventGroupWaitBits(eventos, kBitBaixaPossui, pdFALSE,
                                    pdTRUE, pdMS_TO_TICKS(1000)) &
                kBitBaixaPossui) != 0);
  xTaskNotifyGive(tarefaAltaHandle);
  configASSERT((xEventGroupWaitBits(eventos, kBitAltaSolicitou, pdFALSE,
                                    pdTRUE, pdMS_TO_TICKS(1000)) &
                kBitAltaSolicitou) != 0);

  xEventGroupSetBits(eventos, kBitLiberarBaixa);
  const bool usarMedia = cenario != Cenario::MutexBaseline;
  if (usarMedia) xTaskNotifyGive(tarefaMediaHandle);

  EventBits_t esperados = kBitAltaConcluiu;
  if (usarMedia) esperados |= kBitMediaConcluiu;
  configASSERT((xEventGroupWaitBits(eventos, esperados, pdFALSE, pdTRUE,
                                    pdMS_TO_TICKS(2000)) &
                esperados) == esperados);

  Resultado r{};
  r.cenario = cenario;
  r.repeticao = repeticao;
  r.esperaAltaUs = esperaAltaUs;
  r.janelaBaixaUs = janelaBaixaUs;
  r.janelaMediaUs = janelaMediaUs;
  r.prioridadeEfetivaBaixa = prioridadeEfetivaBaixa;
  return r;
}

void tarefaEnsaio(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    executando = true;
    imprimir("EVENT,START,E10,REPETICOES,%u,ITER_US,%.6f",
             kRepeticoes, iteracoesPorUs);
    imprimir("RESULT_HEADER,scenario,repetition,high_wait_us,low_window_us,medium_window_us,low_effective_priority");

    const Cenario cenarios[] = {Cenario::MutexBaseline,
                                Cenario::MutexHeranca,
                                Cenario::BinarioInversao};
    for (Cenario cenario : cenarios) {
      for (uint32_t repeticao = 1; repeticao <= kRepeticoes; ++repeticao) {
        const Resultado r = executarRepeticao(cenario, repeticao);
        imprimir("RESULT,E10,%s,%lu,%lld,%lld,%lld,%u",
                 nomeCenario(r.cenario),
                 static_cast<unsigned long>(r.repeticao),
                 static_cast<long long>(r.esperaAltaUs),
                 static_cast<long long>(r.janelaBaixaUs),
                 static_cast<long long>(r.janelaMediaUs),
                 static_cast<unsigned>(r.prioridadeEfetivaBaixa));
        vTaskDelay(pdMS_TO_TICKS(5));
      }
    }
    executando = false;
    imprimir("EVENT,END,FIM_NORMAL,CHECKSUM,%lu",
             static_cast<unsigned long>(acumulador));
  }
}

void tarefaComunicacao(void*) {
  String linha;
  linha.reserve(48);
  for (;;) {
    while (Serial.available() > 0) {
      const char c = static_cast<char>(Serial.read());
      if (c == '\r') continue;
      if (c != '\n') {
        if (linha.length() < 47) linha += c;
        continue;
      }
      linha.trim();
      if (linha == "PING") {
        imprimir("ACK,PONG,E10_PRIORITY_INVERSION");
      } else if (linha == "START") {
        if (executando) {
          imprimir("ERRO,E10,OCUPADO");
        } else {
          imprimir("ACK,START,E10");
          xTaskNotifyGive(tarefaEnsaioHandle);
        }
      } else if (linha == "STATUS") {
        imprimir("STATUS,E10,%u,0,0", executando ? 1U : 0U);
      } else if (linha.length() > 0) {
        imprimir("ERRO,E10,COMANDO_INVALIDO");
      }
      linha = "";
    }
    vTaskDelay(pdMS_TO_TICKS(2));
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

  mutexRecurso = xSemaphoreCreateMutex();
  binarioRecurso = xSemaphoreCreateBinary();
  mutexSerial = xSemaphoreCreateMutex();
  eventos = xEventGroupCreate();
  configASSERT(mutexRecurso && binarioRecurso && mutexSerial && eventos);
  xSemaphoreGive(binarioRecurso);

  iteracoesPorUs = calibrarTrabalho();
  configASSERT(isfinite(iteracoesPorUs) && iteracoesPorUs > 0.0);

  criarTarefa(tarefaAlta, "T_Alta", 4096, 6, &tarefaAltaHandle, 1);
  criarTarefa(tarefaMedia, "T_Media", 4096, 4, &tarefaMediaHandle, 1);
  criarTarefa(tarefaBaixa, "T_Baixa", 4096, 2, &tarefaBaixaHandle, 1);
  criarTarefa(tarefaEnsaio, "T_Ensaio", 6144, 4, &tarefaEnsaioHandle, 0);
  criarTarefa(tarefaComunicacao, "T_Comunicacao", 4096, 3, nullptr, 0);

  imprimir("READY,E10_PRIORITY_INVERSION,REPETICOES,%u,LOW_US,%u,MEDIUM_US,%u,ITER_US,%.6f,OUTPUTS_ZERO,1",
           kRepeticoes, kTrabalhoBaixaUs, kTrabalhoMediaUs, iteracoesPorUs);
}

void loop() { vTaskDelete(nullptr); }
