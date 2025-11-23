#include "ble_arm_control.h"
#include "esp_log.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "nvs_flash.h"
#include "position_storage.h"
#include "sequence_player.h"
#include <string.h>

static const char *TAG = "BLE_ARM";

// BLE GATT server attributes
static uint16_t arm_service_handle;
static esp_gatt_if_t arm_gatts_if = ESP_GATT_IF_NONE;
static uint16_t conn_id = 0xFFFF;

// Characteristic handles
static uint16_t rx_char_handle = 0;
static uint16_t tx_char_handle = 0;
static uint16_t joint_char_handle;
static uint16_t all_joints_char_handle;
static uint16_t save_char_handle;
static uint16_t load_char_handle;
static uint16_t play_char_handle;
static uint16_t status_char_handle;

// Service UUID for advertising (128-bit UUID in little-endian format)
static uint8_t service_uuid[16] = {
    0xbc, 0x9a, 0x78, 0x56, 0x34, 0x12, 0x34, 0x12,
    0x34, 0x12, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12
};

// BLE advertising data (main advertisement)
static esp_ble_adv_data_t adv_data = {
    .set_scan_rsp = false,
    .include_name = false,  // Move name to scan response
    .include_txpower = false,  // Reduce size
    .min_interval = 0x0006,
    .max_interval = 0x0010,
    .appearance = 0x00,
    .manufacturer_len = 0,
    .p_manufacturer_data = NULL,
    .service_data_len = 0,
    .p_service_data = NULL,
    .service_uuid_len = 16,
    .p_service_uuid = service_uuid,
    .flag = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
};

// BLE scan response data (includes device name)
static esp_ble_adv_data_t scan_rsp_data = {
    .set_scan_rsp = true,
    .include_name = true,  // Device name in scan response
    .include_txpower = true,
    .appearance = 0x00,
    .manufacturer_len = 0,
    .p_manufacturer_data = NULL,
    .service_data_len = 0,
    .p_service_data = NULL,
    .service_uuid_len = 0,
    .p_service_uuid = NULL,
    .flag = 0,
};

// BLE advertising parameters (fast advertising for quick reconnection)
static esp_ble_adv_params_t adv_params = {
    .adv_int_min = 0x20,  // 20ms (32 * 0.625ms)
    .adv_int_max = 0x30,  // 30ms (48 * 0.625ms) - faster than before
    .adv_type = ADV_TYPE_IND,
    .own_addr_type = BLE_ADDR_TYPE_PUBLIC,
    .channel_map = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

/**
 * Process received BLE command
 */
void ble_process_command(uint8_t *data, uint16_t len) {
    if (len < 1) return;
    
    uint8_t cmd = data[0];
    ESP_LOGI(TAG, "Received command: 0x%02X, length: %d", cmd, len);
    
    switch (cmd) {
        case CMD_SET_JOINT: {
            if (len >= sizeof(ble_joint_cmd_t)) {
                ble_joint_cmd_t *joint_cmd = (ble_joint_cmd_t *)data;
                if (joint_cmd->joint_id < ARM_NUM_JOINTS) {
                    uint8_t servo_id = ARM_SERVO_ID_BASE + joint_cmd->joint_id;
                    esp_err_t ret = sts_servo_set_position(servo_id, joint_cmd->position, 
                                                           joint_cmd->time_ms, joint_cmd->speed);
                    ESP_LOGI(TAG, "Set joint %d (servo %d) to position %d: %s", 
                            joint_cmd->joint_id, servo_id, joint_cmd->position, 
                            ret == ESP_OK ? "OK" : "FAIL");
                } else {
                    ESP_LOGW(TAG, "Invalid joint_id: %d (max is %d)", joint_cmd->joint_id, ARM_NUM_JOINTS - 1);
                }
            }
            break;
        }
        
        case CMD_SET_ALL_JOINTS: {
            if (len >= sizeof(ble_all_joints_cmd_t)) {
                ble_all_joints_cmd_t *all_cmd = (ble_all_joints_cmd_t *)data;
                arm_position_t arm_pos = {0};
                
                for (int i = 0; i < ARM_NUM_JOINTS; i++) {
                    arm_pos.joints[i].position = all_cmd->positions[i];
                    arm_pos.joints[i].time_ms = all_cmd->time_ms;
                    arm_pos.joints[i].speed = all_cmd->speed;
                }
                
                esp_err_t ret = sts_servo_set_arm_position(&arm_pos);
                ESP_LOGI(TAG, "Set all joints: %s", ret == ESP_OK ? "OK" : "FAIL");
            }
            break;
        }
        
        case CMD_SAVE_POSITION: {
            if (len >= sizeof(ble_storage_cmd_t)) {
                ble_storage_cmd_t *storage_cmd = (ble_storage_cmd_t *)data;
                
                // Read current positions from servos
                arm_position_t current_pos = {0};
                current_pos.delay_after_ms = storage_cmd->delay_ms;
                
                for (int i = 0; i < ARM_NUM_JOINTS; i++) {
                    uint16_t position;
                    if (sts_servo_read_position(ARM_SERVO_ID_BASE + i, &position) == ESP_OK) {
                        current_pos.joints[i].position = position;
                        current_pos.joints[i].time_ms = 1000;  // Default 1 second
                        current_pos.joints[i].speed = 1000;    // Default speed
                    }
                }
                
                esp_err_t ret = position_storage_save(storage_cmd->slot_id, &current_pos);
                ESP_LOGI(TAG, "Save position to slot %d: %s", 
                        storage_cmd->slot_id, ret == ESP_OK ? "OK" : "FAIL");
            }
            break;
        }
        
        case CMD_LOAD_POSITION: {
            if (len >= sizeof(ble_storage_cmd_t)) {
                ble_storage_cmd_t *storage_cmd = (ble_storage_cmd_t *)data;
                arm_position_t loaded_pos;
                
                esp_err_t ret = position_storage_load(storage_cmd->slot_id, &loaded_pos);
                if (ret == ESP_OK) {
                    ret = sts_servo_set_arm_position(&loaded_pos);
                    ESP_LOGI(TAG, "Load position from slot %d: %s", 
                            storage_cmd->slot_id, ret == ESP_OK ? "OK" : "FAIL");
                }
            }
            break;
        }
        
        case CMD_START_SEQUENCE: {
            if (len >= sizeof(ble_sequence_cmd_t)) {
                ble_sequence_cmd_t *seq_cmd = (ble_sequence_cmd_t *)data;
                esp_err_t ret = sequence_player_start(seq_cmd->start_slot, 
                                                     seq_cmd->end_slot, 
                                                     seq_cmd->loop);
                ESP_LOGI(TAG, "Start sequence %d-%d (loop=%d): %s", 
                        seq_cmd->start_slot, seq_cmd->end_slot, seq_cmd->loop,
                        ret == ESP_OK ? "OK" : "FAIL");
            }
            break;
        }
        
        case CMD_STOP_SEQUENCE: {
            sequence_player_stop();
            ESP_LOGI(TAG, "Stop sequence");
            break;
        }
        
        case CMD_HOME_POSITION: {
            // Move to center position
            arm_position_t home_pos = {0};
            for (int i = 0; i < ARM_NUM_JOINTS; i++) {
                home_pos.joints[i].position = STS_POSITION_CENTER;
                home_pos.joints[i].time_ms = 2000;
                home_pos.joints[i].speed = 1000;
            }
            esp_err_t ret = sts_servo_set_arm_position(&home_pos);
            ESP_LOGI(TAG, "Move to home position: %s", ret == ESP_OK ? "OK" : "FAIL");
            break;
        }
        
        default:
            ESP_LOGW(TAG, "Unknown command: 0x%02X", cmd);
            break;
    }
}

/**
 * Send status notification
 */
void ble_send_status(void) {
    if (conn_id == 0xFFFF || arm_gatts_if == ESP_GATT_IF_NONE || tx_char_handle == 0) {
        ESP_LOGW(TAG, "Cannot send status: not connected or TX handle not set (handle=%d)", tx_char_handle);
        return;
    }
    
    ble_status_t status = {0};
    status.is_moving = sequence_player_is_running();
    status.current_slot = 0;  // Can be extended
    
    // Read current positions from all servos
    for (int i = 0; i < ARM_NUM_JOINTS; i++) {
        uint16_t position = 2048; // Default to center
        if (sts_servo_read_position(ARM_SERVO_ID_BASE + i, &position) == ESP_OK) {
            status.current_positions[i] = position;
            ESP_LOGD(TAG, "Joint %d (servo %d): position %d", i, ARM_SERVO_ID_BASE + i, position);
        } else {
            ESP_LOGW(TAG, "Failed to read position for joint %d (servo %d)", i, ARM_SERVO_ID_BASE + i);
            status.current_positions[i] = 2048; // Fallback to center
        }
    }
    
    // Send notification via TX characteristic
    esp_err_t ret = esp_ble_gatts_send_indicate(arm_gatts_if, conn_id, tx_char_handle,
                                sizeof(status), (uint8_t *)&status, false);
    
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "Status sent successfully");
    } else {
        ESP_LOGW(TAG, "Failed to send status: %s", esp_err_to_name(ret));
    }
}

/**
 * GATT Server event handler
 */
void ble_gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, 
                             esp_ble_gatts_cb_param_t *param) {
    switch (event) {
        case ESP_GATTS_REG_EVT:
            ESP_LOGI(TAG, "GATT server registered, app_id: %04x", param->reg.app_id);
            arm_gatts_if = gatts_if;
            
            esp_ble_gap_set_device_name(BLE_DEVICE_NAME);
            
            // Configure both advertising data and scan response
            esp_ble_gap_config_adv_data(&adv_data);
            esp_ble_gap_config_adv_data(&scan_rsp_data);
            
            // Create service with 128-bit UUID
            esp_ble_gatts_create_service(gatts_if, &(esp_gatt_srvc_id_t){
                .is_primary = true,
                .id = {
                    .inst_id = 0,
                    .uuid = {
                        .len = ESP_UUID_LEN_128,
                        .uuid = {.uuid128 = {
                            0xbc, 0x9a, 0x78, 0x56, 0x34, 0x12, 0x34, 0x12,
                            0x34, 0x12, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12
                        }}
                    }
                }
            }, 20);
            break;
            
        case ESP_GATTS_CREATE_EVT:
            ESP_LOGI(TAG, "Service created");
            arm_service_handle = param->create.service_handle;
            esp_ble_gatts_start_service(arm_service_handle);
            
            // Add RX characteristic (receives commands from phone)
            esp_ble_gatts_add_char(arm_service_handle,
                &(esp_bt_uuid_t){
                    .len = ESP_UUID_LEN_128,
                    .uuid = {.uuid128 = {
                        0xbd, 0x9a, 0x78, 0x56, 0x34, 0x12, 0x34, 0x12,
                        0x34, 0x12, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12
                    }}
                },
                ESP_GATT_PERM_WRITE,
                ESP_GATT_CHAR_PROP_BIT_WRITE | ESP_GATT_CHAR_PROP_BIT_WRITE_NR,
                NULL,
                NULL);
            
            // Add TX characteristic (sends status to phone)
            esp_ble_gatts_add_char(arm_service_handle,
                &(esp_bt_uuid_t){
                    .len = ESP_UUID_LEN_128,
                    .uuid = {.uuid128 = {
                        0xbe, 0x9a, 0x78, 0x56, 0x34, 0x12, 0x34, 0x12,
                        0x34, 0x12, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12
                    }}
                },
                ESP_GATT_PERM_READ,
                ESP_GATT_CHAR_PROP_BIT_READ | ESP_GATT_CHAR_PROP_BIT_NOTIFY,
                NULL,
                NULL);
            break;
            
        case ESP_GATTS_ADD_CHAR_EVT:
            ESP_LOGI(TAG, "Characteristic added, status: %d, handle: %d", 
                    param->add_char.status, param->add_char.attr_handle);
            
            // Store TX characteristic handle (the second one added)
            if (rx_char_handle == 0) {
                rx_char_handle = param->add_char.attr_handle;
                ESP_LOGI(TAG, "RX characteristic handle: %d", rx_char_handle);
            } else if (tx_char_handle == 0) {
                tx_char_handle = param->add_char.attr_handle;
                ESP_LOGI(TAG, "TX characteristic handle: %d", tx_char_handle);
            }
            break;
            
        case ESP_GATTS_CONNECT_EVT:
            ESP_LOGI(TAG, "Client connected");
            conn_id = param->connect.conn_id;
            
            // Send current positions to the app
            vTaskDelay(pdMS_TO_TICKS(100)); // Brief delay to ensure connection is stable
            ble_send_status();
            break;
            
        case ESP_GATTS_DISCONNECT_EVT:
            ESP_LOGI(TAG, "Client disconnected, reason: 0x%02x", param->disconnect.reason);
            conn_id = 0xFFFF;
            
            // Immediately restart advertising for quick reconnection
            esp_err_t ret = esp_ble_gap_start_advertising(&adv_params);
            if (ret != ESP_OK) {
                ESP_LOGE(TAG, "Failed to start advertising: %s", esp_err_to_name(ret));
            } else {
                ESP_LOGI(TAG, "Advertising restarted");
            }
            break;
            
        case ESP_GATTS_WRITE_EVT:
            ESP_LOGI(TAG, "Write event, length: %d", param->write.len);
            
            // Send response if needed
            if (param->write.need_rsp) {
                esp_ble_gatts_send_response(gatts_if, param->write.conn_id, 
                    param->write.trans_id, ESP_GATT_OK, NULL);
            }
            
            ble_process_command(param->write.value, param->write.len);
            break;
            
        default:
            break;
    }
}

/**
 * GAP event handler
 */
void ble_gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param) {
    switch (event) {
        case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
            esp_ble_gap_start_advertising(&adv_params);
            break;
            
        case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
            if (param->adv_start_cmpl.status == ESP_BT_STATUS_SUCCESS) {
                ESP_LOGI(TAG, "Advertising started");
            }
            break;
            
        default:
            break;
    }
}

/**
 * Initialize BLE for ARM control
 */
esp_err_t ble_arm_init(void) {
    esp_err_t ret;
    
    // Initialize NVS
    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
    
    // Release classic BT memory
    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));
    
    // Initialize BT controller
    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ret = esp_bt_controller_init(&bt_cfg);
    if (ret) {
        ESP_LOGE(TAG, "BT controller init failed: %s", esp_err_to_name(ret));
        return ret;
    }
    
    ret = esp_bt_controller_enable(ESP_BT_MODE_BLE);
    if (ret) {
        ESP_LOGE(TAG, "BT controller enable failed: %s", esp_err_to_name(ret));
        return ret;
    }
    
    // Initialize Bluedroid
    ret = esp_bluedroid_init();
    if (ret) {
        ESP_LOGE(TAG, "Bluedroid init failed: %s", esp_err_to_name(ret));
        return ret;
    }
    
    ret = esp_bluedroid_enable();
    if (ret) {
        ESP_LOGE(TAG, "Bluedroid enable failed: %s", esp_err_to_name(ret));
        return ret;
    }
    
    // Register callbacks
    esp_ble_gatts_register_callback(ble_gatts_event_handler);
    esp_ble_gap_register_callback(ble_gap_event_handler);
    
    // Register GATT application
    esp_ble_gatts_app_register(0);
    
    ESP_LOGI(TAG, "BLE initialized, device name: %s", BLE_DEVICE_NAME);
    
    // Read initial servo positions after a brief delay to let servos stabilize
    vTaskDelay(pdMS_TO_TICKS(500));
    ESP_LOGI(TAG, "Reading initial servo positions...");
    for (int i = 0; i < ARM_NUM_JOINTS; i++) {
        uint16_t position;
        if (sts_servo_read_position(ARM_SERVO_ID_BASE + i, &position) == ESP_OK) {
            ESP_LOGI(TAG, "  Joint %d (Servo %d): position %d", i, ARM_SERVO_ID_BASE + i, position);
        } else {
            ESP_LOGW(TAG, "  Joint %d (Servo %d): failed to read position", i, ARM_SERVO_ID_BASE + i);
        }
    }
    
    return ESP_OK;
}
