# ARM100 BLE Control App

Flutter mobile application to control the ARM100 6-DOF robot arm via Bluetooth Low Energy.

## Features

- **BLE Connection**: Automatic discovery and connection to ARM100_ESP32 device
- **Joint Control**: Individual control of 6 robot joints with real-time sliders
- **Position Management**: Save and load up to 16 arm positions
- **Sequence Player**: Automated playback of position sequences with customizable timing
- **Movement Parameters**: Adjustable speed and time for smooth movements

## Architecture

### Models
- `arm_position.dart`: Position data structure for 6 joints (0-4095 range)
- `ble_commands.dart`: Binary command builders matching ESP32 protocol

### Services
- `arm_ble_service.dart`: BLE connection management and ESP32 communication

### Screens
- `joint_control_screen.dart`: Main control interface with joint sliders
- `position_manager_screen.dart`: Save/load positions to 16 slots
- `sequence_player_screen.dart`: Automated sequence playback

## ESP32 Protocol

The app implements the following BLE commands to match the ESP32 firmware:

| Command | Value | Description | Payload |
|---------|-------|-------------|---------|
| SET_SINGLE_JOINT | 0x01 | Move single joint | jointId(1) + position(2) + speed(2) + time(2) |
| SET_ALL_JOINTS | 0x02 | Move all joints | positions[6](12) + speed(2) + time(2) |
| SAVE_POSITION | 0x03 | Save to slot | slot(1) + positions[6](12) |
| LOAD_POSITION | 0x04 | Load from slot | slot(1) + speed(2) + time(2) |
| PLAY_SEQUENCE | 0x05 | Play sequence | startSlot(1) + endSlot(1) + delayMs(2) + loop(1) |
| STOP_SEQUENCE | 0x06 | Stop playback | - |
| GET_STATUS | 0x07 | Request status | - |
| HOME_POSITION | 0x08 | Center all joints | speed(2) + time(2) |

### BLE Service UUIDs
- Service: `12345678-1234-1234-1234-123456789abc`
- RX Characteristic: `12345678-1234-1234-1234-123456789abd` (Write)
- TX Characteristic: `12345678-1234-1234-1234-123456789abe` (Notify)

## Setup

### Prerequisites
- Flutter SDK ^3.9.2
- Android Studio (for Android) or Xcode (for iOS)
- ESP32 with ARM100 firmware flashed

### Installation

1. Install dependencies:
```bash
cd flattep_app/barm_control
flutter pub get
```

2. For Android, ensure minimum SDK version 21 in `android/app/build.gradle`

3. For iOS, ensure deployment target 11.0 or higher in `ios/Podfile`

### Permissions

**Android** (AndroidManifest.xml):
- `BLUETOOTH` (API ≤30)
- `BLUETOOTH_ADMIN` (API ≤30)
- `BLUETOOTH_SCAN` (API ≥31)
- `BLUETOOTH_CONNECT` (API ≥31)
- `ACCESS_FINE_LOCATION` (API ≤30)

**iOS** (Info.plist):
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

## Usage

### 1. Connect to ARM100

1. Power on the ESP32 with ARM100 connected
2. Open the app
3. Tap "Connect" in the connection card
4. Wait for "Connected to ARM100" status

### 2. Control Joints

- Use sliders to adjust individual joints (0-4095)
- Tap center button to reset joint to middle position (2048)
- Adjust Speed and Time parameters for movement smoothness
- Tap "Send All Joints" to move all joints simultaneously
- Tap "Home" to center all joints

### 3. Save Positions

1. Position the arm using joint sliders
2. Tap the save icon in the app bar
3. Select an empty slot (0-15)
4. Optionally name the position
5. Tap "Save to Slot"

### 4. Load Positions

1. Tap the save icon to open Position Manager
2. Select a saved position slot
3. Tap "Load from Slot"
4. The arm moves to the saved position

### 5. Play Sequences

1. Tap the play icon to open Sequence Player
2. Set Start Slot and End Slot (e.g., 0 to 3)
3. Adjust delay between positions (500-10000ms)
4. Enable "Loop Sequence" for continuous playback
5. Tap "Start Sequence"
6. Tap "Stop Sequence" to end playback

## Joint Mapping

| Joint # | Name | Function |
|---------|------|----------|
| 1 | Base | Rotates entire arm horizontally |
| 2 | Shoulder | Lifts/lowers upper arm |
| 3 | Elbow | Bends middle section |
| 4 | Wrist Pitch | Tilts end effector up/down |
| 5 | Wrist Roll | Rotates end effector |
| 6 | Gripper | Opens/closes gripper |

## Position Values

- **Range**: 0 - 4095 (12-bit)
- **Center**: 2048
- **0**: Minimum position
- **4095**: Maximum position

## Troubleshooting

### Cannot find ARM100
- Ensure ESP32 is powered on
- Check ESP32 is broadcasting as "ARM100_ESP32"
- Verify Bluetooth is enabled on phone
- Grant all location permissions (Android)

### Connection drops
- Move closer to ESP32 (within 10m)
- Avoid RF interference
- Check ESP32 power supply is stable

### Joints not moving
- Verify FE-URT-1 board is powered
- Check UART connections (GPIO32/33)
- Test servos with ESP32 serial monitor
- Ensure servo IDs are 1-6

### App crashes on startup
- Run `flutter clean && flutter pub get`
- Check Android/iOS deployment targets
- Verify permissions are configured

## Building

### Android APK
```bash
flutter build apk --release
```

### iOS IPA
```bash
flutter build ios --release
```

### Debug mode
```bash
flutter run
```

## Development

### Adding new commands

1. Add command enum to `ble_commands.dart`
2. Implement command builder in `BleCommandBuilder`
3. Add method to `ArmBleService`
4. Update UI to call new method

### Modifying UI

All screens use Provider pattern for state management. Modify widgets in `screens/` directory and they will automatically respond to BLE service state changes.

## License

This project is part of the ARM100 robot control system.
