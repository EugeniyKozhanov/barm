#ifndef BLE_ARM_CONTROL_H
#define BLE_ARM_CONTROL_H

#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "sts_servo.h"

// BLE Service UUID: Custom ARM Control Service
#define ARM_SERVICE_UUID          0x1800
#define ARM_CHAR_JOINT_UUID       0x2A00  // Set joint position
#define ARM_CHAR_ALLJOINTS_UUID   0x2A01  // Set all joints at once
#define ARM_CHAR_SAVE_UUID        0x2A02  // Save current position
#define ARM_CHAR_LOAD_UUID        0x2A03  // Load and execute position
#define ARM_CHAR_PLAY_UUID        0x2A04  // Play sequence
#define ARM_CHAR_STATUS_UUID      0x2A05  // Status/feedback

// BLE Configuration
#define BLE_DEVICE_NAME           "ARM100_ESP32"
#define BLE_MAX_MTU               500

// Command types
#define CMD_SET_JOINT             0x01
#define CMD_SET_ALL_JOINTS        0x02
#define CMD_SAVE_POSITION         0x03
#define CMD_LOAD_POSITION         0x04
#define CMD_START_SEQUENCE        0x05
#define CMD_STOP_SEQUENCE         0x06
#define CMD_GET_STATUS            0x07
#define CMD_HOME_POSITION         0x08

// Response codes
#define RESP_OK                   0x00
#define RESP_ERROR                0x01
#define RESP_INVALID_PARAM        0x02
#define RESP_BUSY                 0x03

// Protocol structure for single joint command
typedef struct __attribute__((packed)) {
    uint8_t cmd;           // Command type
    uint8_t joint_id;      // Joint ID (0-5)
    uint16_t position;     // Position (0-4095)
    uint16_t time_ms;      // Time to reach position
    uint16_t speed;        // Speed
} ble_joint_cmd_t;

// Protocol structure for all joints command
typedef struct __attribute__((packed)) {
    uint8_t cmd;           // Command type
    uint16_t positions[ARM_NUM_JOINTS];
    uint16_t time_ms;      // Common time for all joints
    uint16_t speed;        // Common speed for all joints
} ble_all_joints_cmd_t;

// Protocol structure for save/load commands
typedef struct __attribute__((packed)) {
    uint8_t cmd;           // Command type
    uint8_t slot_id;       // Storage slot (0-15)
    uint32_t delay_ms;     // Delay after reaching position (for sequences)
} ble_storage_cmd_t;

// Protocol structure for sequence playback
typedef struct __attribute__((packed)) {
    uint8_t cmd;           // Command type
    uint8_t start_slot;    // First slot
    uint8_t end_slot;      // Last slot
    uint8_t loop;          // Loop playback (0=no, 1=yes)
} ble_sequence_cmd_t;

// Status structure
typedef struct __attribute__((packed)) {
    uint8_t is_moving;
    uint8_t current_slot;
    uint16_t current_positions[ARM_NUM_JOINTS];
} ble_status_t;

// Function prototypes
esp_err_t ble_arm_init(void);
void ble_gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param);
void ble_gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, 
                             esp_ble_gatts_cb_param_t *param);
void ble_process_command(uint8_t *data, uint16_t len);
void ble_send_status(void);

#endif // BLE_ARM_CONTROL_H
