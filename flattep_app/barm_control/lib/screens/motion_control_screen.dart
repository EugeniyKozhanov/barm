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
    
    // Calculate pitch and roll from accelerometer
    // Pitch: rotation around X axis (forward/backward tilt)
    // Roll: rotation around Y axis (left/right tilt)
    double pitch = _accelY; // Forward/backward tilt
    double roll = _accelX;  // Left/right tilt
    
    // Calculate incremental changes
    List<int> newPositions = List.from(_basePositions);
    bool hasMovement = false;
    
    // PITCH affects: Shoulder (Joint 1), Elbow (Joint 2), Wrist Pitch (Joint 4)
    // Only move if pitch exceeds threshold, otherwise hold position
    if (pitch.abs() > _accelThreshold) {
      int pitchDelta = (pitch * 20).toInt(); // Scale factor for smooth movement
      
      if (_jointEnabled[1]) { // Shoulder
        newPositions[1] = (_basePositions[1] + pitchDelta * (_jointInverted[1] ? -1 : 1))
            .clamp(0, 4095);
        hasMovement = true;
      }
      
      if (_jointEnabled[2]) { // Elbow
        newPositions[2] = (_basePositions[2] + pitchDelta * (_jointInverted[2] ? -1 : 1))
            .clamp(0, 4095);
        hasMovement = true;
      }
      
      if (_jointEnabled[4]) { // Wrist Pitch
        newPositions[4] = (_basePositions[4] + pitchDelta * (_jointInverted[4] ? -1 : 1))
            .clamp(0, 4095);
        hasMovement = true;
      }
    }
    // If pitch is below threshold, keep current positions (no movement for pitch joints)
    
    // ROLL affects: Base (Joint 0), Wrist Roll (Joint 3)
    // Only move if roll exceeds threshold, otherwise hold position
    if (roll.abs() > _accelThreshold) {
      int rollDelta = (roll * 20).toInt(); // Scale factor for smooth movement
      
      if (_jointEnabled[0]) { // Base rotation
        newPositions[0] = (_basePositions[0] + rollDelta * (_jointInverted[0] ? -1 : 1))
            .clamp(0, 4095);
        hasMovement = true;
      }
      
      if (_jointEnabled[3]) { // Wrist roll
        newPositions[3] = (_basePositions[3] + rollDelta * (_jointInverted[3] ? -1 : 1))
            .clamp(0, 4095);
        hasMovement = true;
      }
    }
    // If roll is below threshold, keep current positions (no movement for roll joints)
    
    // Update base positions incrementally only for joints that moved
    if (hasMovement) {
      // Only update base positions for enabled joints that had movement
      if (pitch.abs() > _accelThreshold) {
        if (_jointEnabled[1]) _basePositions[1] = newPositions[1];
        if (_jointEnabled[2]) _basePositions[2] = newPositions[2];
        if (_jointEnabled[4]) _basePositions[4] = newPositions[4];
      }
      
      if (roll.abs() > _accelThreshold) {
        if (_jointEnabled[0]) _basePositions[0] = newPositions[0];
        if (_jointEnabled[3]) _basePositions[3] = newPositions[3];
      }
      
      // Send command only if there was actual movement
      bleService.setAllJoints(
        ArmPosition(newPositions),
        speed: 2000,
        time: 100,
      );
    }
    // When phone is horizontal (below threshold), no commands are sent = arm stops
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
                        const SizedBox(width: 100, child: Text('Pitch (Y):', style: TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _accelY.toStringAsFixed(2),
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                              ),
                              const Text(
                                'Forward/Back → Shoulder + Elbow + Wrist Pitch',
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(width: 100, child: Text('Roll (X):', style: TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _accelX.toStringAsFixed(2),
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                              ),
                              const Text(
                                'Left/Right → Base + Wrist Roll',
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Motion mapping explanation
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'Incremental Motion Control',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Pitch (tilt forward/back): Controls Shoulder, Elbow, and Wrist Pitch together',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Text(
                      '• Roll (tilt left/right): Controls Base rotation and Wrist Roll together',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Text(
                      '• Movements are incremental - positions update continuously',
                      style: TextStyle(fontSize: 12),
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
              // Determine which motion controls this joint
              String motionType = '';
              if (index == 0 || index == 3) {
                motionType = 'ROLL';
              } else if (index == 1 || index == 2 || index == 4) {
                motionType = 'PITCH';
              } else if (index == 5) {
                motionType = 'GRIPPER';
              }
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Joint $index',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              motionType,
                              style: TextStyle(
                                fontSize: 10,
                                color: motionType == 'ROLL' ? Colors.orange : 
                                       motionType == 'PITCH' ? Colors.blue : Colors.grey,
                              ),
                            ),
                          ],
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
