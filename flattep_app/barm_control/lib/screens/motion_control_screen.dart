import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/arm_ble_service.dart';
import '../models/arm_position.dart';

class MotionControlScreen extends StatefulWidget {
  const MotionControlScreen({super.key});

  @override
  State<MotionControlScreen> createState() => _MotionControlScreenState();
}

class _MotionControlScreenState extends State<MotionControlScreen> {
  // Motion control state
  bool _isMotionActive = false;
  
  // Joint enable/disable state
  final List<bool> _jointEnabled = List.filled(6, false);
  
  // Joint invert state
  final List<bool> _jointInverted = List.filled(6, false);
  
  // Threshold settings
  double _gyroThreshold = 0.5;
  double _accelThreshold = 2.0;
  
  // Sensor subscriptions
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  
  // Current sensor values
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;
  double _accelX = 0, _accelY = 0, _accelZ = 0;
  
  // Base positions for each joint
  final List<int> _basePositions = [2048, 2048, 2048, 2048, 2048, 2048];
  
  // Timer for sending commands
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _setupVolumeButtonListener();
  }

  @override
  void dispose() {
    _stopMotionControl();
    _gyroSubscription?.cancel();
    _accelSubscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  void _setupVolumeButtonListener() {
    // Note: Volume button handling requires platform-specific implementation
    // This is a placeholder - actual implementation would need method channel
  }

  void _startMotionControl() {
    if (_isMotionActive) return;
    
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    
    // Get current positions as base
    final currentPos = bleService.currentPosition;
    for (int i = 0; i < 6; i++) {
      _basePositions[i] = currentPos.jointPositions[i];
    }
    
    setState(() {
      _isMotionActive = true;
    });
    
    // Start listening to sensors
    _gyroSubscription = gyroscopeEventStream().listen((event) {
      setState(() {
        _gyroX = event.x;
        _gyroY = event.y;
        _gyroZ = event.z;
      });
    });
    
    _accelSubscription = accelerometerEventStream().listen((event) {
      setState(() {
        _accelX = event.x;
        _accelY = event.y;
        _accelZ = event.z;
      });
    });
    
    // Start update timer (20Hz)
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _updateArmFromMotion();
    });
    
    debugPrint('Motion control started');
  }

  void _stopMotionControl() {
    if (!_isMotionActive) return;
    
    setState(() {
      _isMotionActive = false;
    });
    
    _gyroSubscription?.cancel();
    _accelSubscription?.cancel();
    _updateTimer?.cancel();
    
    debugPrint('Motion control stopped');
  }

  void _updateArmFromMotion() {
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    if (!bleService.isConnected) return;
    
    // Calculate new positions based on sensor data
    List<int> newPositions = List.from(_basePositions);
    
    // Map gyroscope to joint movements
    // Gyro X -> Joint 0 (base rotation)
    if (_jointEnabled[0]) {
      double delta = _gyroZ * 100; // Scale factor
      if (delta.abs() > _gyroThreshold) {
        newPositions[0] = (_basePositions[0] + (delta * (_jointInverted[0] ? -1 : 1)).toInt())
            .clamp(0, 4095);
      }
    }
    
    // Gyro Y -> Joint 1 (shoulder)
    if (_jointEnabled[1]) {
      double delta = _gyroY * 100;
      if (delta.abs() > _gyroThreshold) {
        newPositions[1] = (_basePositions[1] + (delta * (_jointInverted[1] ? -1 : 1)).toInt())
            .clamp(0, 4095);
      }
    }
    
    // Gyro X -> Joint 2 (elbow)
    if (_jointEnabled[2]) {
      double delta = _gyroX * 100;
      if (delta.abs() > _gyroThreshold) {
        newPositions[2] = (_basePositions[2] + (delta * (_jointInverted[2] ? -1 : 1)).toInt())
            .clamp(0, 4095);
      }
    }
    
    // Accel for remaining joints
    if (_jointEnabled[3]) {
      double delta = _accelX * 50;
      if (delta.abs() > _accelThreshold) {
        newPositions[3] = (_basePositions[3] + (delta * (_jointInverted[3] ? -1 : 1)).toInt())
            .clamp(0, 4095);
      }
    }
    
    if (_jointEnabled[4]) {
      double delta = _accelY * 50;
      if (delta.abs() > _accelThreshold) {
        newPositions[4] = (_basePositions[4] + (delta * (_jointInverted[4] ? -1 : 1)).toInt())
            .clamp(0, 4095);
      }
    }
    
    // Send command
    bleService.setAllJoints(
      ArmPosition(newPositions),
      speed: 2000,
      time: 100,
    );
  }

  void _openGripper() {
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    if (!bleService.isConnected) return;
    
    // Joint 5 is gripper - open position
    bleService.setSingleJoint(5, 1500, speed: 1500, time: 500);
    debugPrint('Gripper opened');
  }

  void _resetBasePositions() {
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    final currentPos = bleService.currentPosition;
    setState(() {
      for (int i = 0; i < 6; i++) {
        _basePositions[i] = currentPos.jointPositions[i];
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Base positions reset')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Motion Control'),
        actions: [
          IconButton(
            icon: Icon(_isMotionActive ? Icons.stop : Icons.play_arrow),
            onPressed: _isMotionActive ? _stopMotionControl : _startMotionControl,
            tooltip: _isMotionActive ? 'Stop' : 'Start',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetBasePositions,
            tooltip: 'Reset base positions',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            Card(
              color: _isMotionActive ? Colors.green.shade100 : Colors.grey.shade200,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _isMotionActive ? Icons.sensors : Icons.sensors_off,
                      size: 32,
                      color: _isMotionActive ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isMotionActive ? 'Motion Control Active' : 'Motion Control Inactive',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Vol+: Toggle control | Vol-: Open gripper',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Sensor readings
            const Text('Sensor Readings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 100, child: Text('Gyroscope:')),
                        Expanded(
                          child: Text(
                            'X: ${_gyroX.toStringAsFixed(2)}  Y: ${_gyroY.toStringAsFixed(2)}  Z: ${_gyroZ.toStringAsFixed(2)}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 100, child: Text('Accelerometer:')),
                        Expanded(
                          child: Text(
                            'X: ${_accelX.toStringAsFixed(2)}  Y: ${_accelY.toStringAsFixed(2)}  Z: ${_accelZ.toStringAsFixed(2)}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Joint configuration
            const Text('Joint Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            ...List.generate(6, (index) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          'Joint $index',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Checkbox(
                              value: _jointEnabled[index],
                              onChanged: (value) {
                                setState(() {
                                  _jointEnabled[index] = value ?? false;
                                });
                              },
                            ),
                            const Text('Enable'),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Checkbox(
                            value: _jointInverted[index],
                            onChanged: (value) {
                              setState(() {
                                _jointInverted[index] = value ?? false;
                              });
                            },
                          ),
                          const Text('Invert'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            
            const SizedBox(height: 24),
            
            // Threshold settings
            const Text('Threshold Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 150, child: Text('Gyro Threshold:')),
                        Expanded(
                          child: Slider(
                            value: _gyroThreshold,
                            min: 0.1,
                            max: 2.0,
                            divisions: 19,
                            label: _gyroThreshold.toStringAsFixed(1),
                            onChanged: (value) {
                              setState(() {
                                _gyroThreshold = value;
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(_gyroThreshold.toStringAsFixed(1)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 150, child: Text('Accel Threshold:')),
                        Expanded(
                          child: Slider(
                            value: _accelThreshold,
                            min: 0.5,
                            max: 5.0,
                            divisions: 45,
                            label: _accelThreshold.toStringAsFixed(1),
                            onChanged: (value) {
                              setState(() {
                                _accelThreshold = value;
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(_accelThreshold.toStringAsFixed(1)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Manual controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openGripper,
                    icon: const Icon(Icons.open_in_full),
                    label: const Text('Open Gripper'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
