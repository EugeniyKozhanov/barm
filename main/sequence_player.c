#include "sequence_player.h"
#include "position_storage.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <inttypes.h>

static const char *TAG = "SEQ_PLAYER";

// Player state variables
static player_state_t player_state = PLAYER_IDLE;
static TaskHandle_t player_task_handle = NULL;
static SemaphoreHandle_t player_mutex = NULL;

static uint8_t current_start_slot = 0;
static uint8_t current_end_slot = 0;
static bool current_loop = false;

/**
 * Sequence player task
 */
static void sequence_player_task(void *pvParameters) {
    ESP_LOGI(TAG, "Sequence player task started");
    
    while (true) {
        if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
            if (player_state != PLAYER_RUNNING) {
                xSemaphoreGive(player_mutex);
                vTaskDelay(pdMS_TO_TICKS(100));
                continue;
            }
            xSemaphoreGive(player_mutex);
        }
        
        // Play sequence
        do {
            for (uint8_t slot = current_start_slot; slot <= current_end_slot; slot++) {
                // Check if stopped
                if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
                    if (player_state != PLAYER_RUNNING) {
                        xSemaphoreGive(player_mutex);
                        goto sequence_end;
                    }
                    xSemaphoreGive(player_mutex);
                }
                
                // Check if slot exists
                if (!position_storage_slot_exists(slot)) {
                    ESP_LOGW(TAG, "Slot %d doesn't exist, skipping", slot);
                    continue;
                }
                
                // Load and execute position
                arm_position_t position;
                if (position_storage_load(slot, &position) == ESP_OK) {
                    ESP_LOGI(TAG, "Playing slot %d", slot);
                    
                    // Send position to servos
                    sts_servo_set_arm_position(&position);
                    
                    // Calculate total movement time
                    uint16_t max_time = 0;
                    for (int i = 0; i < ARM_NUM_JOINTS; i++) {
                        if (position.joints[i].time_ms > max_time) {
                            max_time = position.joints[i].time_ms;
                        }
                    }
                    
                    // Wait for movement to complete
                    vTaskDelay(pdMS_TO_TICKS(max_time));
                    
                    // Wait for additional delay if specified
                    if (position.delay_after_ms > 0) {
                        ESP_LOGD(TAG, "Delay %" PRIu32 " ms", position.delay_after_ms);
                        vTaskDelay(pdMS_TO_TICKS(position.delay_after_ms));
                    }
                } else {
                    ESP_LOGE(TAG, "Failed to load slot %d", slot);
                }
            }
        } while (current_loop && player_state == PLAYER_RUNNING);
        
sequence_end:
        // Sequence finished
        if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
            if (player_state == PLAYER_RUNNING && !current_loop) {
                player_state = PLAYER_IDLE;
                ESP_LOGI(TAG, "Sequence playback complete");
            }
            xSemaphoreGive(player_mutex);
        }
        
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

/**
 * Initialize sequence player
 */
esp_err_t sequence_player_init(void) {
    player_mutex = xSemaphoreCreateMutex();
    if (player_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_FAIL;
    }
    
    // Create player task
    BaseType_t ret = xTaskCreate(sequence_player_task, "seq_player", 4096, 
                                 NULL, 5, &player_task_handle);
    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create task");
        return ESP_FAIL;
    }
    
    ESP_LOGI(TAG, "Sequence player initialized");
    return ESP_OK;
}

/**
 * Start sequence playback
 */
esp_err_t sequence_player_start(uint8_t start_slot, uint8_t end_slot, bool loop) {
    if (start_slot > end_slot || end_slot >= MAX_STORAGE_SLOTS) {
        ESP_LOGE(TAG, "Invalid slot range: %d-%d", start_slot, end_slot);
        return ESP_ERR_INVALID_ARG;
    }
    
    if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
        current_start_slot = start_slot;
        current_end_slot = end_slot;
        current_loop = loop;
        player_state = PLAYER_RUNNING;
        xSemaphoreGive(player_mutex);
    }
    
    ESP_LOGI(TAG, "Started sequence playback: slots %d-%d, loop=%d", 
             start_slot, end_slot, loop);
    return ESP_OK;
}

/**
 * Stop sequence playback
 */
void sequence_player_stop(void) {
    if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
        player_state = PLAYER_IDLE;
        xSemaphoreGive(player_mutex);
    }
    ESP_LOGI(TAG, "Sequence playback stopped");
}

/**
 * Pause sequence playback
 */
void sequence_player_pause(void) {
    if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
        if (player_state == PLAYER_RUNNING) {
            player_state = PLAYER_PAUSED;
        }
        xSemaphoreGive(player_mutex);
    }
    ESP_LOGI(TAG, "Sequence playback paused");
}

/**
 * Resume sequence playback
 */
void sequence_player_resume(void) {
    if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
        if (player_state == PLAYER_PAUSED) {
            player_state = PLAYER_RUNNING;
        }
        xSemaphoreGive(player_mutex);
    }
    ESP_LOGI(TAG, "Sequence playback resumed");
}

/**
 * Check if player is running
 */
bool sequence_player_is_running(void) {
    bool running = false;
    if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
        running = (player_state == PLAYER_RUNNING);
        xSemaphoreGive(player_mutex);
    }
    return running;
}

/**
 * Get current player state
 */
player_state_t sequence_player_get_state(void) {
    player_state_t state = PLAYER_IDLE;
    if (xSemaphoreTake(player_mutex, portMAX_DELAY)) {
        state = player_state;
        xSemaphoreGive(player_mutex);
    }
    return state;
}
