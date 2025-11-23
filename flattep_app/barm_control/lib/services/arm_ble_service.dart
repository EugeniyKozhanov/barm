import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/arm_position.dart';
import '../models/ble_commands.dart';

class ArmBleService extends ChangeNotifier {
  static const String targetDeviceName = "ARM100_ESP32";
  static const String serviceUuid = "12345678-1234-1234-1234-123456789abc";
  static const String rxCharacteristicUuid = "12345678-1234-1234-1234-123456789abd";
  static const String txCharacteristicUuid = "12345678-1234-1234-1234-123456789abe";
  
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _notificationSubscription;
  
  bool _isScanning = false;
  bool _isConnected = false;
  String _statusMessage = "Not connected";
  ArmPosition _currentPosition = ArmPosition.center();
  
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  String get statusMessage => _statusMessage;
  ArmPosition get currentPosition => _currentPosition;
  BluetoothDevice? get device => _device;
  
  ArmBleService() {
    _init();
  }
  
  Future<void> _init() async {
    // Listen to bluetooth adapter state
    _stateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on && _isConnected) {
        _handleDisconnection();
      }
    });
  }
  
  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      
      return statuses.values.every((status) => status.isGranted);
    }
    return true;
  }
  
  Future<void> startScan() async {
    if (_isScanning) return;
    
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      _updateStatus("Bluetooth permissions not granted");
      return;
    }
    
    // Check if bluetooth is available
    if (await FlutterBluePlus.isSupported == false) {
      _updateStatus("Bluetooth not supported");
      return;
    }
    
    // Check if bluetooth is on
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _updateStatus("Please enable Bluetooth");
      return;
    }
    
    _isScanning = true;
    _updateStatus("Scanning for ARM100...");
    
    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final deviceName = result.device.platformName;
          final advName = result.advertisementData.advName;
          final serviceUuids = result.advertisementData.serviceUuids;
          final macAddress = result.device.remoteId.toString();
          
          debugPrint('Found device: MAC=$macAddress, platformName="$deviceName", advName="$advName", services=$serviceUuids');
          
          // Check device name (both platformName and advertisementData name)
          bool nameMatch = deviceName == targetDeviceName || advName == targetDeviceName;
          
          // Check MAC address (from ESP32 log: b0:a7:32:27:cc:9a)
          bool macMatch = macAddress.toLowerCase().replaceAll(':', '') == 'b0a73227cc9a';
          
          // Check if device advertises our service UUID
          bool serviceMatch = serviceUuids.any((uuid) => 
            uuid.toString().toLowerCase() == serviceUuid.toLowerCase()
          );
          
          if (nameMatch || serviceMatch || macMatch) {
            debugPrint('Found target device! Name match: $nameMatch, Service match: $serviceMatch, MAC match: $macMatch');
            stopScan();
            connect(result.device);
            break;
          }
        }
      });
      
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),  // Longer timeout for Linux
        androidUsesFineLocation: false,  // Not needed on Linux
        // Don't filter by service on Linux - BlueZ issues
        // withServices: [Guid(serviceUuid)],
      );
      
      await Future.delayed(const Duration(seconds: 15));
      
      if (!_isConnected) {
        stopScan();
        _updateStatus("ARM100 not found");
      }
    } catch (e) {
      _updateStatus("Scan error: $e");
      _isScanning = false;
      notifyListeners();
    }
  }
  
  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    notifyListeners();
  }
  
  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    _updateStatus("Connecting to ${device.platformName}...");
    
    try {
      // Listen to connection state
      _connectionSubscription = device.connectionState.listen((state) {
        debugPrint('Connection state changed: $state');
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
      
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      
      debugPrint('Connected, discovering services...');
      _updateStatus("Discovering services...");
      
      List<BluetoothService> services = await device.discoverServices();
      debugPrint('Found ${services.length} services');
      
      for (var service in services) {
        debugPrint('Service UUID: ${service.uuid}');
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          debugPrint('Found ARM service!');
          for (var characteristic in service.characteristics) {
            final uuid = characteristic.uuid.toString().toLowerCase();
            debugPrint('Characteristic UUID: $uuid');
            if (uuid == rxCharacteristicUuid.toLowerCase()) {
              _rxCharacteristic = characteristic;
              debugPrint('Found RX characteristic');
            } else if (uuid == txCharacteristicUuid.toLowerCase()) {
              _txCharacteristic = characteristic;
              debugPrint('Found TX characteristic');
              // Enable notifications
              await characteristic.setNotifyValue(true);
              debugPrint('Notifications enabled');
              // Listen to notifications (status updates from ESP32)
              _notificationSubscription = characteristic.onValueReceived.listen((value) {
                debugPrint('Received notification: ${value.length} bytes');
                _handleStatusUpdate(value);
              });
            }
          }
        }
      }
      
      if (_rxCharacteristic == null || _txCharacteristic == null) {
        debugPrint('Service not found: RX=${_rxCharacteristic != null}, TX=${_txCharacteristic != null}');
        await device.disconnect();
        _updateStatus("Service not found on device");
        return;
      }
      
      _isConnected = true;
      _updateStatus("Connected to ARM100");
      debugPrint('Successfully connected to ARM100');
      
      // Wait a bit for notification subscription to be fully active
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Request initial status to sync positions
      debugPrint('Requesting initial status...');
      await _sendCommand(BleCommandBuilder.getStatus());
      
    } catch (e) {
      debugPrint('Connection error: $e');
      _updateStatus("Connection failed: $e");
      _device = null;
      _rxCharacteristic = null;
      _txCharacteristic = null;
    }
  }
  
  Future<void> disconnect() async {
    if (_device != null) {
      await _device!.disconnect();
    }
    _handleDisconnection();
  }
  
  void _handleDisconnection() {
    _isConnected = false;
    _device = null;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _updateStatus("Disconnected");
  }
  
  void _handleStatusUpdate(List<int> data) {
    // Parse status data from ESP32
    // Format: is_moving (1 byte), current_slot (1 byte), positions (6 x 2 bytes = 12 bytes)
    // Total: 14 bytes
    debugPrint('_handleStatusUpdate called with ${data.length} bytes: $data');
    if (data.length >= 14) {
      final isMoving = data[0] != 0;
      final currentSlot = data[1];
      
      // Extract 6 joint positions (16-bit little-endian values)
      final positions = List<int>.filled(6, 2048);
      for (int i = 0; i < 6; i++) {
        final offset = 2 + (i * 2);
        final low = data[offset];
        final high = data[offset + 1];
        positions[i] = low | (high << 8);
        debugPrint('Joint $i: low=$low, high=$high, position=${positions[i]}');
      }
      
      debugPrint('Parsed positions: $positions');
      
      // Validate positions before creating ArmPosition
      bool valid = true;
      for (int i = 0; i < positions.length; i++) {
        if (positions[i] < 0 || positions[i] > 4095) {
          debugPrint('ERROR: Invalid position at joint $i: ${positions[i]} (must be 0-4095)');
          valid = false;
        }
      }
      
      if (valid) {
        _currentPosition = ArmPosition(positions);
        debugPrint('Status update - Moving: $isMoving, Slot: $currentSlot, Positions: $positions');
        notifyListeners();
      } else {
        debugPrint('WARNING: Skipping invalid position update');
      }
    } else {
      debugPrint('WARNING: Status data too short (${data.length} bytes, expected 14)');
    }
  }
  
  void _updateStatus(String status) {
    _statusMessage = status;
    notifyListeners();
  }
  
  Future<bool> _sendCommand(Uint8List command) async {
    if (!_isConnected || _rxCharacteristic == null) {
      debugPrint('ERROR: Cannot send command - not connected or RX characteristic null');
      _updateStatus("Not connected");
      return false;
    }
    
    try {
      debugPrint('Sending command: ${command.toList()} (${command.length} bytes)');
      await _rxCharacteristic!.write(command, withoutResponse: true);
      debugPrint('Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('ERROR sending command: $e');
      _updateStatus("Send error: $e");
      return false;
    }
  }
  
  Future<bool> setSingleJoint(int jointId, int position, {int speed = 1000, int time = 1000}) async {
    final command = BleCommandBuilder.setSingleJoint(jointId, position, speed, time);
    final success = await _sendCommand(command);
    if (success) {
      _currentPosition.jointPositions[jointId] = position;
      notifyListeners();
    }
    return success;
  }
  
  Future<bool> setAllJoints(ArmPosition position, {int speed = 1000, int time = 1000}) async {
    final command = BleCommandBuilder.setAllJoints(position.jointPositions, speed, time);
    final success = await _sendCommand(command);
    if (success) {
      _currentPosition = position;
      notifyListeners();
    }
    return success;
  }
  
  Future<bool> savePosition(int slot, ArmPosition position) async {
    final command = BleCommandBuilder.savePosition(slot, position.jointPositions);
    return await _sendCommand(command);
  }
  
  Future<bool> loadPosition(int slot, {int speed = 1000, int time = 1000}) async {
    final command = BleCommandBuilder.loadPosition(slot, speed, time);
    return await _sendCommand(command);
  }
  
  Future<bool> playSequence(int startSlot, int endSlot, int delayMs, bool loop) async {
    final command = BleCommandBuilder.playSequence(startSlot, endSlot, delayMs, loop);
    return await _sendCommand(command);
  }
  
  Future<bool> stopSequence() async {
    final command = BleCommandBuilder.stopSequence();
    return await _sendCommand(command);
  }
  
  Future<bool> homePosition({int speed = 1000, int time = 1000}) async {
    final command = BleCommandBuilder.homePosition(speed, time);
    final success = await _sendCommand(command);
    if (success) {
      _currentPosition = ArmPosition.center();
      notifyListeners();
    }
    return success;
  }
  
  Future<bool> setTorque(bool enable) async {
    final command = BleCommandBuilder.setTorque(enable);
    return await _sendCommand(command);
  }
  
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _stateSubscription?.cancel();
    _connectionSubscription?.cancel();
    _notificationSubscription?.cancel();
    disconnect();
    super.dispose();
  }
}
