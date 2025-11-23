idf_component_register(SRCS "main.c"
                            "sts_servo.c"
                            "ble_arm_control.c"
                            "position_storage.c"
                            "sequence_player.c"
                    INCLUDE_DIRS "."
                    PRIV_REQUIRES nvs_flash bt esp_driver_uart)