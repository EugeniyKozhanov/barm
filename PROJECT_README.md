# ARM100 6DOF Robot Arm BLE Control System

ESP32-based BLE controller for ARM100 6-axis robot arm using STS3214 servos via FE-URT-1 board.

## Hardware Setup

- **ESP32 DevKit** (ESP32-D0WD-V3)
- **FE-URT-1 Control Board** (connected to STS3214 servos)
- **ARM100 6DOF Robot Arm** with STS3214 servos

### Wiring

```
ESP32          FE-URT-1
GPIO33 (TX) -> RX
GPIO32 (RX) -> TX
GND         -> GND
```

## Features

- **BLE Control**: Easy connection via Bluetooth Low Energy
- **Joint Control**: Individual joint positioning or simultaneous control
- **Position Storage**: Save up to 16 positions in non-volatile memory
- **Sequence Playback**: Create and replay movement sequences with timing
- **Real-time Feedback**: Position and status monitoring

## BLE Protocol

### Device Name
`ARM100_ESP32`

### Commands

#### 1. Set Single Joint (CMD: 0x01)
```c
struct {
    uint8_t cmd = 0x01;
    uint8_t joint_id;      // 0-5
    uint16_t position;     // 0-4095
    uint16_t time_ms;      // Time to reach position
    uint16_t speed;        // Movement speed
}
```

#### 2. Set All Joints (CMD: 0x02)
```c
struct {
    uint8_t cmd = 0x02;
    uint16_t positions[6]; // Positions for all 6 joints
    uint16_t time_ms;      // Common time
    uint16_t speed;        // Common speed
}
```

#### 3. Save Position (CMD: 0x03)
```c
struct {
    uint8_t cmd = 0x03;
    uint8_t slot_id;       // 0-15
    uint32_t delay_ms;     // Delay after reaching (for sequences)
}
```

#### 4. Load Position (CMD: 0x04)
```c
struct {
    uint8_t cmd = 0x04;
    uint8_t slot_id;       // 0-15
}
```

#### 5. Play Sequence (CMD: 0x05)
```c
struct {
    uint8_t cmd = 0x05;
    uint8_t start_slot;    // First slot
    uint8_t end_slot;      // Last slot
    uint8_t loop;          // 0=no loop, 1=loop
}
```

#### 6. Stop Sequence (CMD: 0x06)
```c
struct {
    uint8_t cmd = 0x06;
}
```

#### 7. Home Position (CMD: 0x08)
```c
struct {
    uint8_t cmd = 0x08;
}
```

## Building and Flashing

### Prerequisites
- ESP-IDF v5.4.2 or later
- Python 3.8+

### Build
```bash
cd /path/to/barm
. $HOME/esp/v5.4.2/esp-idf/export.sh
idf.py build
```

### Flash
```bash
idf.py -p /dev/ttyUSB0 flash
```

### Monitor
```bash
idf.py -p /dev/ttyUSB0 monitor
```

## Project Structure

```
barm/
├── main/
│   ├── main.c                 # Main application
│   ├── sts_servo.c/h          # STS3214 servo protocol
│   ├── ble_arm_control.c/h    # BLE GATT server
│   ├── position_storage.c/h   # NVS position storage
│   ├── sequence_player.c/h    # Sequence playback engine
│   └── CMakeLists.txt
├── CMakeLists.txt
├── sdkconfig
└── README.md
```

## Usage Example

### Via BLE (Python example using bleak)

```python
import asyncio
from bleak import BleakClient, BleakScanner
import struct

async def control_arm():
    # Find device
    device = await BleakScanner.find_device_by_name("ARM100_ESP32")
    
    async with BleakClient(device) as client:
        # Set joint 0 to position 2048 (center)
        cmd = struct.pack("<BBHHH", 0x01, 0, 2048, 1000, 1000)
        await client.write_gatt_char(CHAR_UUID, cmd)
        
        # Set all joints to center position
        cmd = struct.pack("<BHHHHHHHHHH", 0x02, 
                          2048, 2048, 2048, 2048, 2048, 2048,
                          2000, 1000)
        await client.write_gatt_char(CHAR_UUID, cmd)
        
        # Save current position to slot 0
        cmd = struct.pack("<BBI", 0x03, 0, 500)  # 500ms delay
        await client.write_gatt_char(CHAR_UUID, cmd)
        
        # Play sequence slots 0-5 with loop
        cmd = struct.pack("<BBBB", 0x05, 0, 5, 1)
        await client.write_gatt_char(CHAR_UUID, cmd)

asyncio.run(control_arm())
```

## STS3214 Servo Specifications

- **Position Range**: 0-4095 (12-bit)
- **Center Position**: 2048
- **Communication**: TTL Serial (1 Mbps)
- **Protocol**: Feetech STS servo protocol

## Troubleshooting

### Servos not responding
1. Check UART connections (TX/RX may be swapped)
2. Verify baud rate (1000000 bps)
3. Check servo IDs (default: 1-6)
4. Verify power supply to servos

### BLE not visible
1. Ensure Bluetooth is enabled in sdkconfig
2. Check that device name appears in BLE scanner
3. Verify ESP32 is not in a boot loop

### Position not saving
1. Ensure NVS partition is available
2. Check flash memory is not full
3. Verify slot_id is in range 0-15

## License

This project is open source.

## Author

Created for ARM100 6DOF robot arm control via ESP32 and BLE.
