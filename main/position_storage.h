#ifndef POSITION_STORAGE_H
#define POSITION_STORAGE_H

#include "sts_servo.h"
#include "nvs.h"

#define MAX_STORAGE_SLOTS    16
#define NVS_NAMESPACE        "arm_storage"

// Function prototypes
esp_err_t position_storage_init(void);
esp_err_t position_storage_save(uint8_t slot_id, arm_position_t *position);
esp_err_t position_storage_load(uint8_t slot_id, arm_position_t *position);
esp_err_t position_storage_clear(uint8_t slot_id);
esp_err_t position_storage_clear_all(void);
bool position_storage_slot_exists(uint8_t slot_id);

#endif // POSITION_STORAGE_H
