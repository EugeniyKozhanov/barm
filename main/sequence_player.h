#ifndef SEQUENCE_PLAYER_H
#define SEQUENCE_PLAYER_H

#include "sts_servo.h"
#include <stdbool.h>

// Sequence player state
typedef enum {
    PLAYER_IDLE,
    PLAYER_RUNNING,
    PLAYER_PAUSED
} player_state_t;

// Function prototypes
esp_err_t sequence_player_init(void);
esp_err_t sequence_player_start(uint8_t start_slot, uint8_t end_slot, bool loop);
void sequence_player_stop(void);
void sequence_player_pause(void);
void sequence_player_resume(void);
bool sequence_player_is_running(void);
player_state_t sequence_player_get_state(void);

#endif // SEQUENCE_PLAYER_H
