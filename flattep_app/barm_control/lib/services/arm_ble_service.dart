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
          if (result.device.platformName == targetDeviceName) {
            stopScan();
            connect(result.device);
            break;
          }
        }
      });
      
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
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
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
      
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      
      _updateStatus("Discovering services...");
      
      List<BluetoothService> services = await device.discoverServices();
      
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          for (var characteristic in service.characteristics) {
            final uuid = characteristic.uuid.toString().toLowerCase();
            if (uuid == rxCharacteristicUuid.toLowerCase()) {
              _rxCharacteristic = characteristic;
            } else if (uuid == txCharacteristicUuid.toLowerCase()) {
              _txCharacteristic = characteristic;
              // Enable notifications
              await characteristic.setNotifyValue(true);
            }
          }
        }
      }
      
      if (_rxCharacteristic == null || _txCharacteristic == null) {
        await device.disconnect();
        _updateStatus("Service not found on device");
        return;
      }
      
      _isConnected = true;
      _updateStatus("Connected to ARM100");
      
    } catch (e) {
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
    _updateStatus("Disconnected");
  }
  
  void _updateStatus(String status) {
    _statusMessage = status;
    notifyListeners();
  }
  
  Future<bool> _sendCommand(Uint8List command) async {
    if (!_isConnected || _rxCharacteristic == null) {
      _updateStatus("Not connected");
      return false;
    }
    
    try {
      await _rxCharacteristic!.write(command, withoutResponse: false);
      return true;
    } catch (e) {
      _updateStatus("Send error: $e");
      return false;
    }
  }
  
  Future<bool> setSingleJoint(int jointId, int position, {int speed = 1000, int time = 1000}) async {
    final command = BleCommandBuilder.setSingleJoint(jointId, position, speed, time);
    final success = await _sendCommand(command);
    if (success) {
      _currentPosition.jointPositions[jointId - 1] = position;
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
  
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _stateSubscription?.cancel();
    _connectionSubscription?.cancel();
    disconnect();
    super.dispose();
  }
}
