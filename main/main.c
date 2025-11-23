#include <stdio.h>
#include <inttypes.h>
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "sts_servo.h"
#include "ble_arm_control.h"
#include "position_storage.h"
#include "sequence_player.h"

static const char *TAG = "ARM100_MAIN";

/**
 * Main application entry point
 */
void app_main(void)
{
    ESP_LOGI(TAG, "ARM100 6DOF BLE Control System Starting...");
    ESP_LOGI(TAG, "Hardware: ESP32 + FE-URT-1 + STS3214 Servos");
    ESP_LOGI(TAG, "UART: TX=GPIO33, RX=GPIO32");
    
    // Initialize UART communication with FE-URT-1 board
    ESP_LOGI(TAG, "Initializing UART for servo communication...");
    esp_err_t ret = sts_servo_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize UART: %s", esp_err_to_name(ret));
        return;
    }
    
    // Initialize position storage (NVS)
    ESP_LOGI(TAG, "Initializing position storage...");
    ret = position_storage_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize storage: %s", esp_err_to_name(ret));
        return;
    }
    
    // Initialize sequence player
    ESP_LOGI(TAG, "Initializing sequence player...");
    ret = sequence_player_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize sequence player: %s", esp_err_to_name(ret));
        return;
    }
    
    // Initialize BLE
    ESP_LOGI(TAG, "Initializing BLE...");
    ret = ble_arm_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize BLE: %s", esp_err_to_name(ret));
        return;
    }
    
    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "ARM100 System Ready!");
    ESP_LOGI(TAG, "BLE Device Name: ARM100_ESP32");
    ESP_LOGI(TAG, "Connect via BLE to control the robot arm");
    ESP_LOGI(TAG, "===========================================");
    
    // Ping all servos to check connectivity
    ESP_LOGI(TAG, "Checking servo connectivity...");
    for (int i = 0; i < ARM_NUM_JOINTS; i++) {
        uint8_t servo_id = ARM_SERVO_ID_BASE + i;
        if (sts_servo_ping(servo_id) == ESP_OK) {
            ESP_LOGI(TAG, "  Joint %d (ID %d): OK", i, servo_id);
        } else {
            ESP_LOGW(TAG, "  Joint %d (ID %d): No response", i, servo_id);
        }
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    
    // Main loop - monitor system status
    uint32_t counter = 0;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        
        // Periodic status log
        if (sequence_player_is_running()) {
            ESP_LOGI(TAG, "Status: Sequence playing... (%" PRIu32 ")", counter);
        } else {
            ESP_LOGD(TAG, "Status: Idle (%" PRIu32 ")", counter);
        }
        counter++;
    }
}