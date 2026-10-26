#include <Arduino.h>

#include "esp_timer.h"

#if !defined(STR_E9_INSTRUMENTATION)
#error "Compile este arquivo somente no ambiente e9_instrumentation."
#endif

namespace {

constexpr uint8_t kPinAquecedor = 25;
constexpr uint8_t kPinCooler = 26;
constexpr uint32_t kBaud = 115200;
constexpr size_t kLoteAmostras = 300;
constexpr size_t kLotesAquecimento = 10;

struct RegistroTrace {
  uint32_t sequencia;
  int64_t liberacaoUs;
  int64_t inicioUs;
  int64_t terminoUs;
  int64_t deadlineUs;
  int64_t bloqueioUs;
  uint8_t perdeuDeadline;
  uint8_t ocupacaoFila;
  uint16_t descartes;
};

struct Resultado {
  const char* nome;
  uint32_t operacoesPorLote;
  double mediaNs;
  uint32_t p50Ns;
  uint32_t p95Ns;
  uint32_t p99Ns;
  uint32_t maxNs;
};

enum class Operacao : uint8_t {
  BaselineLcg,
  TimerPair,
  TraceBuild,
  QueueSendReceive,
  QueueFullFail,
  CriticalCounter,
  SnprintfTrace,
  TracePipeline,
};

enum class Estado : uint8_t { Ocioso = 0, Executando = 1, Concluido = 2 };

QueueHandle_t filaTeste = nullptr;
SemaphoreHandle_t mutexSerial = nullptr;
TaskHandle_t tarefaBenchmarkHandle = nullptr;
portMUX_TYPE muxContador = portMUX_INITIALIZER_UNLOCKED;
volatile uint32_t acumulador = 0x13579BDFU;
volatile uint32_t contadorProtegido = 0;
volatile Estado estado = Estado::Ocioso;

void imprimir(const char* formato, ...) {
  char linha[320];
  va_list args;
  va_start(args, formato);
  vsnprintf(linha, sizeof(linha), formato, args);
  va_end(args);

  if (xSemaphoreTake(mutexSerial, pdMS_TO_TICKS(250)) == pdTRUE) {
    Serial.println(linha);
    xSemaphoreGive(mutexSerial);
  }
}

void ordenar(uint32_t* valores, size_t n) {
  for (size_t i = 1; i < n; ++i) {
    const uint32_t atual = valores[i];
    size_t j = i;
    while (j > 0 && valores[j - 1] > atual) {
      valores[j] = valores[j - 1];
      --j;
    }
    valores[j] = atual;
  }
}

uint32_t percentil(const uint32_t* ordenados, size_t n, uint32_t pct) {
  size_t indice = (static_cast<size_t>(pct) * n + 99U) / 100U;
  if (indice == 0) indice = 1;
  if (indice > n) indice = n;
  return ordenados[indice - 1];
}

void esvaziarFila() {
  RegistroTrace item{};
  while (xQueueReceive(filaTeste, &item, 0) == pdTRUE) {
  }
}

void executarOperacoes(Operacao operacao, uint32_t quantidade) {
  RegistroTrace registro{};
  char buffer[220];

  for (uint32_t i = 0; i < quantidade; ++i) {
    switch (operacao) {
      case Operacao::BaselineLcg:
        acumulador = acumulador * 1664525U + 1013904223U;
        break;

      case Operacao::TimerPair: {
        const int64_t a = esp_timer_get_time();
        const int64_t b = esp_timer_get_time();
        acumulador ^= static_cast<uint32_t>(a ^ b);
        break;
      }

      case Operacao::TraceBuild: {
        const int64_t base = static_cast<int64_t>(i) * 1000;
        registro = {i, base, base + 3, base + 17, 600000, 0, 0, 1, 0};
        acumulador ^= registro.sequencia +
                     static_cast<uint32_t>(registro.terminoUs);
        break;
      }

      case Operacao::QueueSendReceive:
        registro.sequencia = i;
        if (xQueueSend(filaTeste, &registro, 0) == pdTRUE) {
          xQueueReceive(filaTeste, &registro, 0);
          acumulador ^= registro.sequencia;
        }
        break;

      case Operacao::QueueFullFail:
        registro.sequencia = i;
        acumulador += xQueueSend(filaTeste, &registro, 0) == pdTRUE ? 1U : 3U;
        break;

      case Operacao::CriticalCounter:
        portENTER_CRITICAL(&muxContador);
        ++contadorProtegido;
        portEXIT_CRITICAL(&muxContador);
        break;

      case Operacao::SnprintfTrace:
        snprintf(buffer, sizeof(buffer),
                 "TRACE,AQUISICAO,%lu,%lld,%lld,%lld,%lld,%lld,%u,%u,%u",
                 static_cast<unsigned long>(i),
                 static_cast<long long>(1000000LL + i),
                 static_cast<long long>(1000100LL + i),
                 static_cast<long long>(1000400LL + i),
                 static_cast<long long>(600000LL),
                 static_cast<long long>(300LL), 0U, 1U, 0U);
        acumulador ^= static_cast<uint32_t>(buffer[0] + buffer[10]);
        break;

      case Operacao::TracePipeline: {
        const int64_t inicio = esp_timer_get_time();
        registro = {i, inicio, inicio + 3, inicio + 17, 600000, 0, 0, 1, 0};
        if (xQueueSend(filaTeste, &registro, 0) == pdTRUE) {
          xQueueReceive(filaTeste, &registro, 0);
        }
        portENTER_CRITICAL(&muxContador);
        ++contadorProtegido;
        portEXIT_CRITICAL(&muxContador);
        acumulador ^= registro.sequencia;
        break;
      }
    }
  }
}

Resultado medir(const char* nome, Operacao operacao,
                uint32_t operacoesPorLote, bool manterFilaCheia = false) {
  static uint32_t amostrasNs[kLoteAmostras];
  esvaziarFila();

  RegistroTrace sentinela{};
  if (manterFilaCheia) {
    configASSERT(xQueueSend(filaTeste, &sentinela, 0) == pdTRUE);
  }

  for (size_t lote = 0; lote < kLotesAquecimento; ++lote) {
    executarOperacoes(operacao, operacoesPorLote);
  }

  uint64_t somaNs = 0;
  for (size_t lote = 0; lote < kLoteAmostras; ++lote) {
    const int64_t inicioUs = esp_timer_get_time();
    executarOperacoes(operacao, operacoesPorLote);
    const int64_t terminoUs = esp_timer_get_time();
    const uint64_t duracaoNs =
        static_cast<uint64_t>(terminoUs - inicioUs) * 1000ULL;
    amostrasNs[lote] = static_cast<uint32_t>(
        (duracaoNs + operacoesPorLote / 2U) / operacoesPorLote);
    somaNs += amostrasNs[lote];
    taskYIELD();
  }

  if (manterFilaCheia) esvaziarFila();
  ordenar(amostrasNs, kLoteAmostras);

  Resultado resultado{};
  resultado.nome = nome;
  resultado.operacoesPorLote = operacoesPorLote;
  resultado.mediaNs = static_cast<double>(somaNs) / kLoteAmostras;
  resultado.p50Ns = percentil(amostrasNs, kLoteAmostras, 50);
  resultado.p95Ns = percentil(amostrasNs, kLoteAmostras, 95);
  resultado.p99Ns = percentil(amostrasNs, kLoteAmostras, 99);
  resultado.maxNs = amostrasNs[kLoteAmostras - 1];
  return resultado;
}

void tarefaBenchmark(void*) {
  constexpr size_t kQuantidadeResultados = 8;
  Resultado resultados[kQuantidadeResultados]{};

  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    estado = Estado::Executando;
    imprimir("EVENT,START,E9,CPU_MHZ,%u,PRIORIDADE,%u,LOTES,%u",
             getCpuFrequencyMhz(), uxTaskPriorityGet(nullptr),
             static_cast<unsigned>(kLoteAmostras));

    resultados[0] =
        medir("BASELINE_LCG", Operacao::BaselineLcg, 10000);
    resultados[1] =
        medir("ESP_TIMER_PAIR", Operacao::TimerPair, 1000);
    resultados[2] =
        medir("TRACE_BUILD", Operacao::TraceBuild, 5000);
    resultados[3] =
        medir("QUEUE_SEND_RECEIVE", Operacao::QueueSendReceive, 100);
    resultados[4] =
        medir("QUEUE_FULL_FAIL", Operacao::QueueFullFail, 1000, true);
    resultados[5] =
        medir("CRITICAL_COUNTER", Operacao::CriticalCounter, 1000);
    resultados[6] =
        medir("SNPRINTF_TRACE", Operacao::SnprintfTrace, 20);
    resultados[7] =
        medir("TRACE_PIPELINE", Operacao::TracePipeline, 100);

    imprimir("RESULT_HEADER,scenario,operation,batches,ops_per_batch,mean_ns,p50_ns,p95_ns,p99_ns,max_ns");
    for (const Resultado& r : resultados) {
      imprimir("RESULT,E9,%s,%u,%lu,%.3f,%lu,%lu,%lu,%lu", r.nome,
               static_cast<unsigned>(kLoteAmostras),
               static_cast<unsigned long>(r.operacoesPorLote), r.mediaNs,
               static_cast<unsigned long>(r.p50Ns),
               static_cast<unsigned long>(r.p95Ns),
               static_cast<unsigned long>(r.p99Ns),
               static_cast<unsigned long>(r.maxNs));
    }
    imprimir("EVENT,END,FIM_NORMAL,CHECKSUM,%lu,COUNTER,%lu",
             static_cast<unsigned long>(acumulador),
             static_cast<unsigned long>(contadorProtegido));
    estado = Estado::Concluido;
  }
}

void tarefaComunicacao(void*) {
  String linha;
  linha.reserve(64);

  for (;;) {
    while (Serial.available() > 0) {
      const char c = static_cast<char>(Serial.read());
      if (c == '\r') continue;
      if (c != '\n') {
        if (linha.length() < 63) linha += c;
        continue;
      }

      linha.trim();
      if (linha == "PING") {
        imprimir("ACK,PONG,E9_INSTRUMENTATION");
      } else if (linha == "START") {
        if (estado == Estado::Executando) {
          imprimir("ERRO,E9,OCUPADO");
        } else {
          imprimir("ACK,START,E9");
          xTaskNotifyGive(tarefaBenchmarkHandle);
        }
      } else if (linha == "STATUS") {
        imprimir("STATUS,E9,%u", static_cast<unsigned>(estado));
      } else if (linha.length() > 0) {
        imprimir("ERRO,E9,COMANDO_INVALIDO");
      }
      linha = "";
    }
    vTaskDelay(pdMS_TO_TICKS(2));
  }
}

}  // namespace

void setup() {
  digitalWrite(kPinAquecedor, LOW);
  digitalWrite(kPinCooler, LOW);
  pinMode(kPinAquecedor, OUTPUT);
  pinMode(kPinCooler, OUTPUT);

  Serial.begin(kBaud);
  Serial.setTimeout(20);
  delay(300);

  filaTeste = xQueueCreate(1, sizeof(RegistroTrace));
  mutexSerial = xSemaphoreCreateMutex();
  configASSERT(filaTeste && mutexSerial);

  BaseType_t ok = xTaskCreatePinnedToCore(tarefaBenchmark, "T_Benchmark", 8192,
                                          nullptr, 4,
                                          &tarefaBenchmarkHandle, 1);
  configASSERT(ok == pdPASS);
  ok = xTaskCreatePinnedToCore(tarefaComunicacao, "T_Comunicacao", 4096,
                               nullptr, 3, nullptr, 0);
  configASSERT(ok == pdPASS);

  imprimir("READY,E9_INSTRUMENTATION,CPU_MHZ,%u,BATCHES,%u,OUTPUTS_ZERO,1",
           getCpuFrequencyMhz(), static_cast<unsigned>(kLoteAmostras));
}

void loop() { vTaskDelete(nullptr); }
