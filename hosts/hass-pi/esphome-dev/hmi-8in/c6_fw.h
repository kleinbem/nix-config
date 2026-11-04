#pragma once
// Reads the C6 co-processor firmware version in its own task: factory C6
// firmware may never answer, and the main loop must not wait for it. The
// version is RPC-only: espressif/esp-hosted-mcu#251.
#include <cstdio>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_hosted.h"
#include "esp_hosted_host_fw_ver.h"
#include "esp_chip_info.h"

namespace c6_fw {
inline char text[96] = "C6 firmware: checking...";
inline volatile bool changed = true;

inline void task_(void *) {
  vTaskDelay(pdMS_TO_TICKS(20000));
  esp_hosted_coprocessor_fwver_t v{};
  if (esp_hosted_get_coprocessor_fwversion(&v) == ESP_OK) {
    snprintf(text, sizeof(text), "C6 firmware: esp-hosted %u.%u.%u   (P4 side: %u.%u.%u)", (unsigned) v.major1,
             (unsigned) v.minor1, (unsigned) v.patch1, (unsigned) ESP_HOSTED_VERSION_MAJOR_1, (unsigned) ESP_HOSTED_VERSION_MINOR_1,
             (unsigned) ESP_HOSTED_VERSION_PATCH_1);
  } else {
    snprintf(text, sizeof(text), "C6 firmware: no answer (old factory firmware)   (P4 side: %u.%u.%u)",
             (unsigned) ESP_HOSTED_VERSION_MAJOR_1, (unsigned) ESP_HOSTED_VERSION_MINOR_1,
             (unsigned) ESP_HOSTED_VERSION_PATCH_1);
  }
  changed = true;
  vTaskDelete(nullptr);
}

inline void start() { xTaskCreate(task_, "c6_fw", 4096, nullptr, 1, nullptr); }
}  // namespace c6_fw
