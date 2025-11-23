#include "position_storage.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "POS_STORAGE";
static nvs_handle_t storage_handle;

/**
 * Initialize position storage system
 */
esp_err_t position_storage_init(void) {
    esp_err_t ret = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &storage_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS: %s", esp_err_to_name(ret));
        return ret;
    }
    
    ESP_LOGI(TAG, "Position storage initialized");
    return ESP_OK;
}

/**
 * Save ARM position to storage slot
 */
esp_err_t position_storage_save(uint8_t slot_id, arm_position_t *position) {
    if (slot_id >= MAX_STORAGE_SLOTS) {
        ESP_LOGE(TAG, "Invalid slot ID: %d", slot_id);
        return ESP_ERR_INVALID_ARG;
    }
    
    char key[16];
    snprintf(key, sizeof(key), "pos_%d", slot_id);
    
    esp_err_t ret = nvs_set_blob(storage_handle, key, position, sizeof(arm_position_t));
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to save to slot %d: %s", slot_id, esp_err_to_name(ret));
        return ret;
    }
    
    ret = nvs_commit(storage_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit: %s", esp_err_to_name(ret));
        return ret;
    }
    
    ESP_LOGI(TAG, "Saved position to slot %d", slot_id);
    return ESP_OK;
}

/**
 * Load ARM position from storage slot
 */
esp_err_t position_storage_load(uint8_t slot_id, arm_position_t *position) {
    if (slot_id >= MAX_STORAGE_SLOTS) {
        ESP_LOGE(TAG, "Invalid slot ID: %d", slot_id);
        return ESP_ERR_INVALID_ARG;
    }
    
    char key[16];
    snprintf(key, sizeof(key), "pos_%d", slot_id);
    
    size_t required_size = sizeof(arm_position_t);
    esp_err_t ret = nvs_get_blob(storage_handle, key, position, &required_size);
    
    if (ret == ESP_ERR_NVS_NOT_FOUND) {
        ESP_LOGW(TAG, "Slot %d is empty", slot_id);
        return ret;
    } else if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to load from slot %d: %s", slot_id, esp_err_to_name(ret));
        return ret;
    }
    
    ESP_LOGI(TAG, "Loaded position from slot %d", slot_id);
    return ESP_OK;
}

/**
 * Clear specific storage slot
 */
esp_err_t position_storage_clear(uint8_t slot_id) {
    if (slot_id >= MAX_STORAGE_SLOTS) {
        return ESP_ERR_INVALID_ARG;
    }
    
    char key[16];
    snprintf(key, sizeof(key), "pos_%d", slot_id);
    
    esp_err_t ret = nvs_erase_key(storage_handle, key);
    if (ret == ESP_OK) {
        nvs_commit(storage_handle);
        ESP_LOGI(TAG, "Cleared slot %d", slot_id);
    }
    
    return ret;
}

/**
 * Clear all storage slots
 */
esp_err_t position_storage_clear_all(void) {
    esp_err_t ret = nvs_erase_all(storage_handle);
    if (ret == ESP_OK) {
        nvs_commit(storage_handle);
        ESP_LOGI(TAG, "Cleared all positions");
    }
    return ret;
}

/**
 * Check if storage slot exists
 */
bool position_storage_slot_exists(uint8_t slot_id) {
    if (slot_id >= MAX_STORAGE_SLOTS) {
        return false;
    }
    
    char key[16];
    snprintf(key, sizeof(key), "pos_%d", slot_id);
    
    size_t required_size;
    esp_err_t ret = nvs_get_blob(storage_handle, key, NULL, &required_size);
    
    return (ret == ESP_OK);
}
