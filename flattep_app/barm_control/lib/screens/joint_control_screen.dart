import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/arm_ble_service.dart';
import '../models/arm_position.dart';
import 'position_manager_screen.dart';
import 'sequence_player_screen.dart';
import 'teaching_mode_screen.dart';

class JointControlScreen extends StatefulWidget {
  const JointControlScreen({super.key});

  @override
  State<JointControlScreen> createState() => _JointControlScreenState();
}

class _JointControlScreenState extends State<JointControlScreen> {
  final List<double> _jointValues = List.filled(6, 2048.0);
  double _speed = 1000.0;
  double _time = 1000.0;
  
  @override
  void initState() {
    super.initState();
    // Sync slider values with BLE service's current position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bleService = Provider.of<ArmBleService>(context, listen: false);
      setState(() {
        for (int i = 0; i < 6; i++) {
          _jointValues[i] = bleService.currentPosition.jointPositions[i].toDouble();
        }
      });
      
      // Listen to position updates
      bleService.addListener(_updatePositions);
    });
  }
  
  @override
  void dispose() {
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    bleService.removeListener(_updatePositions);
    super.dispose();
  }
  
  void _updatePositions() {
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    if (mounted) {
      setState(() {
        for (int i = 0; i < 6; i++) {
          _jointValues[i] = bleService.currentPosition.jointPositions[i].toDouble();
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARM100 Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PositionManagerScreen(
                  currentPosition: ArmPosition(_jointValues.map((v) => v.toInt()).toList()),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SequencePlayerScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<ArmBleService>(
        builder: (context, bleService, child) {
          return Column(
            children: [
              _buildConnectionCard(bleService),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildSpeedTimeControls(),
                        const SizedBox(height: 16),
                        ...List.generate(6, (index) => _buildJointSlider(index, bleService)),
                        const SizedBox(height: 16),
                        _buildControlButtons(bleService),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildConnectionCard(ArmBleService bleService) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: bleService.isConnected ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  bleService.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: bleService.isConnected ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bleService.statusMessage,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!bleService.isConnected && !bleService.isScanning)
                  ElevatedButton(
                    onPressed: bleService.startScan,
                    child: const Text('Connect'),
                  ),
                if (bleService.isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (bleService.isConnected)
                  ElevatedButton(
                    onPressed: bleService.disconnect,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSpeedTimeControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Movement Parameters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Speed: ${_speed.toInt()}'),
                      Slider(
                        value: _speed,
                        min: 100,
                        max: 3000,
                        divisions: 29,
                        label: _speed.toInt().toString(),
                        onChanged: (value) => setState(() => _speed = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Time: ${_time.toInt()} ms'),
                      Slider(
                        value: _time,
                        min: 100,
                        max: 5000,
                        divisions: 49,
                        label: _time.toInt().toString(),
                        onChanged: (value) => setState(() => _time = value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildJointSlider(int index, ArmBleService bleService) {
    final jointNames = ['Base', 'Shoulder', 'Elbow', 'Wrist Pitch', 'Wrist Roll', 'Gripper'];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Joint ${index + 1}: ${jointNames[index]}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('${_jointValues[index].toInt()}'),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _jointValues[index],
                    min: 0,
                    max: 4095,
                    divisions: 4095,
                    onChanged: (value) {
                      setState(() => _jointValues[index] = value);
                    },
                    onChangeEnd: (value) {
                      if (bleService.isConnected) {
                        bleService.setSingleJoint(
                          index, // Send 0-5 (not index+1)
                          value.toInt(),
                          speed: _speed.toInt(),
                          time: _time.toInt(),
                        );
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.center_focus_strong),
                  tooltip: 'Center',
                  onPressed: () {
                    setState(() => _jointValues[index] = 2048.0);
                    if (bleService.isConnected) {
                      bleService.setSingleJoint(
                        index, // Send 0-5 (not index+1)
                        2048,
                        speed: _speed.toInt(),
                        time: _time.toInt(),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildControlButtons(ArmBleService bleService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: bleService.isConnected
                        ? () async {
                            final position = ArmPosition(_jointValues.map((v) => v.toInt()).toList());
                            await bleService.setAllJoints(
                              position,
                              speed: _speed.toInt(),
                              time: _time.toInt(),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Send All Joints'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: bleService.isConnected
                        ? () async {
                            await bleService.homePosition(
                              speed: _speed.toInt(),
                              time: _time.toInt(),
                            );
                            setState(() {
                              for (int i = 0; i < 6; i++) {
                                _jointValues[i] = 2048.0;
                              }
                            });
                          }
                        : null,
                    icon: const Icon(Icons.home),
                    label: const Text('Home'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
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
