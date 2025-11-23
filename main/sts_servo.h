#ifndef STS_SERVO_H
#define STS_SERVO_H

#include <stdint.h>
#include "driver/uart.h"

// STS3214 Servo Protocol Commands
#define STS_FRAME_HEADER          0xFF
#define STS_BROADCAST_ID          0xFE
#define STS_CMD_PING              0x01
#define STS_CMD_READ              0x02
#define STS_CMD_WRITE             0x03
#define STS_CMD_REG_WRITE         0x04
#define STS_CMD_ACTION            0x05
#define STS_CMD_SYNC_WRITE        0x83

// STS3214 Memory Table Addresses
#define STS_ADDR_ID               0x05
#define STS_ADDR_BAUD_RATE        0x06
#define STS_ADDR_GOAL_POSITION_L  0x2A
#define STS_ADDR_GOAL_POSITION_H  0x2B
#define STS_ADDR_GOAL_TIME_L      0x2C
#define STS_ADDR_GOAL_TIME_H      0x2D
#define STS_ADDR_GOAL_SPEED_L     0x2E
#define STS_ADDR_GOAL_SPEED_H     0x2F
#define STS_ADDR_PRESENT_POSITION_L 0x38
#define STS_ADDR_PRESENT_POSITION_H 0x39

// ARM Configuration
#define ARM_NUM_JOINTS            6
#define ARM_SERVO_ID_BASE         1

// Position limits (0-4095 for STS3214)
#define STS_POSITION_MIN          0
#define STS_POSITION_MAX          4095
#define STS_POSITION_CENTER       2048

// Speed limits (0-4095)
#define STS_SPEED_MIN             0
#define STS_SPEED_MAX             4095

// UART Configuration
#define UART_PORT                 UART_NUM_1
#define UART_TX_PIN               33
#define UART_RX_PIN               32
#define UART_BAUD_RATE            1000000
#define UART_BUF_SIZE             1024

// Structure for joint position
typedef struct {
    uint16_t position;  // 0-4095
    uint16_t time_ms;   // Time to reach position in milliseconds
    uint16_t speed;     // Speed (0-4095)
} joint_position_t;

// Structure for complete ARM position
typedef struct {
    joint_position_t joints[ARM_NUM_JOINTS];
    uint32_t delay_after_ms;  // Delay after reaching this position
} arm_position_t;

// Function prototypes
esp_err_t sts_servo_init(void);
esp_err_t sts_servo_ping(uint8_t servo_id);
esp_err_t sts_servo_set_position(uint8_t servo_id, uint16_t position, uint16_t time_ms, uint16_t speed);
esp_err_t sts_servo_read_position(uint8_t servo_id, uint16_t *position);
esp_err_t sts_servo_sync_write_position(arm_position_t *arm_pos);
esp_err_t sts_servo_set_arm_position(arm_position_t *arm_pos);
uint8_t sts_calculate_checksum(uint8_t *data, uint8_t length);

#endif // STS_SERVO_H
