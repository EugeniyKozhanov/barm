#include "sts_servo.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>

static const char *TAG = "STS_SERVO";

/**
 * Calculate checksum for STS servo protocol
 */
uint8_t sts_calculate_checksum(uint8_t *data, uint8_t length) {
    uint8_t checksum = 0;
    for (int i = 2; i < length; i++) {
        checksum += data[i];
    }
    return ~checksum;
}

/**
 * Initialize UART for STS servo communication
 */
esp_err_t sts_servo_init(void) {
    uart_config_t uart_config = {
        .baud_rate = UART_BAUD_RATE,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
    };

    ESP_ERROR_CHECK(uart_param_config(UART_PORT, &uart_config));
    ESP_ERROR_CHECK(uart_set_pin(UART_PORT, UART_TX_PIN, UART_RX_PIN, 
                                  UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    ESP_ERROR_CHECK(uart_driver_install(UART_PORT, UART_BUF_SIZE, 
                                        UART_BUF_SIZE, 0, NULL, 0));

    ESP_LOGI(TAG, "UART initialized: TX=%d, RX=%d, Baud=%d", 
             UART_TX_PIN, UART_RX_PIN, UART_BAUD_RATE);
    
    return ESP_OK;
}

/**
 * Send ping command to servo
 */
esp_err_t sts_servo_ping(uint8_t servo_id) {
    uint8_t packet[6];
    packet[0] = STS_FRAME_HEADER;
    packet[1] = STS_FRAME_HEADER;
    packet[2] = servo_id;
    packet[3] = 2;  // Length
    packet[4] = STS_CMD_PING;
    packet[5] = sts_calculate_checksum(packet, 5);

    uart_write_bytes(UART_PORT, (const char *)packet, 6);
    
    // Wait for response
    uint8_t response[6];
    int len = uart_read_bytes(UART_PORT, response, 6, pdMS_TO_TICKS(100));
    
    if (len == 6) {
        ESP_LOGI(TAG, "Servo %d responded to ping", servo_id);
        return ESP_OK;
    }
    
    ESP_LOGW(TAG, "Servo %d no response", servo_id);
    return ESP_FAIL;
}

/**
 * Set servo position with time and speed
 */
esp_err_t sts_servo_set_position(uint8_t servo_id, uint16_t position, 
                                  uint16_t time_ms, uint16_t speed) {
    // Clamp values
    if (position > STS_POSITION_MAX) position = STS_POSITION_MAX;
    if (speed > STS_SPEED_MAX) speed = STS_SPEED_MAX;

    uint8_t packet[13];
    packet[0] = STS_FRAME_HEADER;
    packet[1] = STS_FRAME_HEADER;
    packet[2] = servo_id;
    packet[3] = 9;  // Length
    packet[4] = STS_CMD_WRITE;
    packet[5] = STS_ADDR_GOAL_POSITION_L;
    packet[6] = position & 0xFF;          // Position Low
    packet[7] = (position >> 8) & 0xFF;   // Position High
    packet[8] = time_ms & 0xFF;           // Time Low
    packet[9] = (time_ms >> 8) & 0xFF;    // Time High
    packet[10] = speed & 0xFF;            // Speed Low
    packet[11] = (speed >> 8) & 0xFF;     // Speed High
    packet[12] = sts_calculate_checksum(packet, 12);

    int written = uart_write_bytes(UART_PORT, (const char *)packet, 13);
    
    if (written == 13) {
        ESP_LOGD(TAG, "Servo %d: pos=%d, time=%dms, speed=%d", 
                 servo_id, position, time_ms, speed);
        return ESP_OK;
    }
    
    return ESP_FAIL;
}

/**
 * Read current servo position
 */
esp_err_t sts_servo_read_position(uint8_t servo_id, uint16_t *position) {
    // Initialize to invalid value
    *position = 0xFFFF;
    
    uint8_t packet[8];
    packet[0] = STS_FRAME_HEADER;
    packet[1] = STS_FRAME_HEADER;
    packet[2] = servo_id;
    packet[3] = 4;  // Length
    packet[4] = STS_CMD_READ;
    packet[5] = STS_ADDR_PRESENT_POSITION_L;
    packet[6] = 2;  // Read 2 bytes
    packet[7] = sts_calculate_checksum(packet, 7);

    uart_write_bytes(UART_PORT, (const char *)packet, 8);
    
    // Wait for response
    uint8_t response[8];
    int len = uart_read_bytes(UART_PORT, response, 8, pdMS_TO_TICKS(100));
    
    if (len >= 8) {
        *position = response[5] | (response[6] << 8);
        return ESP_OK;
    }
    
    return ESP_FAIL;
}

/**
 * Set position for all ARM joints using sync write
 */
esp_err_t sts_servo_sync_write_position(arm_position_t *arm_pos) {
    // Sync write packet: header + id + length + cmd + addr + param_len + (id + data)*n + checksum
    uint8_t packet[8 + ARM_NUM_JOINTS * 7];
    int idx = 0;
    
    packet[idx++] = STS_FRAME_HEADER;
    packet[idx++] = STS_FRAME_HEADER;
    packet[idx++] = STS_BROADCAST_ID;
    packet[idx++] = 4 + ARM_NUM_JOINTS * 7;  // Length
    packet[idx++] = STS_CMD_SYNC_WRITE;
    packet[idx++] = STS_ADDR_GOAL_POSITION_L;
    packet[idx++] = 6;  // Parameter length per servo (pos + time + speed)
    
    // Add data for each joint
    for (int i = 0; i < ARM_NUM_JOINTS; i++) {
        packet[idx++] = ARM_SERVO_ID_BASE + i;
        packet[idx++] = arm_pos->joints[i].position & 0xFF;
        packet[idx++] = (arm_pos->joints[i].position >> 8) & 0xFF;
        packet[idx++] = arm_pos->joints[i].time_ms & 0xFF;
        packet[idx++] = (arm_pos->joints[i].time_ms >> 8) & 0xFF;
        packet[idx++] = arm_pos->joints[i].speed & 0xFF;
        packet[idx++] = (arm_pos->joints[i].speed >> 8) & 0xFF;
    }
    
    int checksum_idx = idx;
    packet[idx++] = sts_calculate_checksum(packet, checksum_idx);
    
    int written = uart_write_bytes(UART_PORT, (const char *)packet, idx);
    
    if (written == idx) {
        ESP_LOGI(TAG, "Sync write complete for all joints");
        return ESP_OK;
    }
    
    return ESP_FAIL;
}

/**
 * Set ARM position (wrapper function)
 */
esp_err_t sts_servo_set_arm_position(arm_position_t *arm_pos) {
    return sts_servo_sync_write_position(arm_pos);
}
