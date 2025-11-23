import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/arm_ble_service.dart';
import '../models/teaching_position.dart';

class TeachingModeScreen extends StatefulWidget {
  const TeachingModeScreen({super.key});

  @override
  State<TeachingModeScreen> createState() => _TeachingModeScreenState();
}

class _TeachingModeScreenState extends State<TeachingModeScreen> {
  bool _torqueEnabled = true;
  List<TeachingPosition> _positions = [];
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  bool _loopPlayback = false;
  final _uuid = const Uuid();
  
  @override
  void initState() {
    super.initState();
    _loadPositions();
  }
  
  Future<void> _loadPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('teaching_session');
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final session = TeachingSession.fromJsonString(jsonString);
        setState(() {
          _positions = session.positions;
        });
      } catch (e) {
        debugPrint('Error loading teaching session: $e');
      }
    }
  }
  
  Future<void> _savePositions() async {
    final prefs = await SharedPreferences.getInstance();
    final session = TeachingSession(_positions);
    await prefs.setString('teaching_session', session.toJsonString());
  }
  
  Future<void> _toggleTorque() async {
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    final newState = !_torqueEnabled;
    final success = await bleService.setTorque(newState);
    if (success) {
      setState(() {
        _torqueEnabled = newState;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Torque ${newState ? "enabled" : "disabled"}')),
      );
    }
  }
  
  Future<void> _saveCurrentPosition() async {
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    final position = bleService.currentPosition;
    
    // Show dialog to name the position
    final TextEditingController nameController = TextEditingController(
      text: 'Position ${_positions.length + 1}',
    );
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Position'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Position Name',
            hintText: 'Enter a name for this position',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (name != null && name.isNotEmpty) {
      final teachingPos = TeachingPosition(
        id: _uuid.v4(),
        name: name,
        position: position,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _positions.add(teachingPos);
      });
      
      await _savePositions();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $name')),
      );
    }
  }
  
  Future<void> _deletePosition(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Position'),
        content: Text('Delete "${_positions[index].name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      setState(() {
        _positions.removeAt(index);
      });
      await _savePositions();
    }
  }
  
  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: const Text('Delete all saved positions?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      setState(() {
        _positions.clear();
      });
      await _savePositions();
    }
  }
  
  Future<void> _playSequence() async {
    if (_positions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No positions to play')),
      );
      return;
    }
    
    setState(() {
      _isPlaying = true;
    });
    
    final bleService = Provider.of<ArmBleService>(context, listen: false);
    
    do {
      for (int i = 0; i < _positions.length; i++) {
        if (!_isPlaying) break;
        
        final pos = _positions[i];
        setState(() {}); // Trigger UI update to show current position
        
        // Move to position
        await bleService.setAllJoints(
          pos.position,
          speed: (1000 * _playbackSpeed).toInt(),
          time: (1000 / _playbackSpeed).toInt(),
        );
        
        // Wait for movement to complete plus delay
        await Future.delayed(Duration(
          milliseconds: ((1000 + pos.delayAfterMs) / _playbackSpeed).toInt(),
        ));
      }
    } while (_loopPlayback && _isPlaying);
    
    setState(() {
      _isPlaying = false;
    });
  }
  
  void _stopSequence() {
    setState(() {
      _isPlaying = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teaching Mode'),
        actions: [
          if (_positions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAll,
              tooltip: 'Clear all positions',
            ),
        ],
      ),
      body: Column(
        children: [
          // Control Panel
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Torque Toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Torque',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Switch(
                        value: _torqueEnabled,
                        onChanged: (_) => _toggleTorque(),
                      ),
                    ],
                  ),
                  const Divider(),
                  Text(
                    _torqueEnabled
                        ? 'Motors are locked. Disable torque to move arm manually.'
                        : 'Motors are free. Move arm by hand to teach positions.',
                    style: TextStyle(
                      color: _torqueEnabled ? Colors.blue : Colors.green,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Save Position Button
                  ElevatedButton.icon(
                    onPressed: _torqueEnabled ? null : _saveCurrentPosition,
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Save Current Position'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Playback Controls
          if (_positions.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Playback Controls',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    
                    // Speed Slider
                    Row(
                      children: [
                        const Text('Speed:'),
                        Expanded(
                          child: Slider(
                            value: _playbackSpeed,
                            min: 0.1,
                            max: 2.0,
                            divisions: 19,
                            label: '${_playbackSpeed.toStringAsFixed(1)}x',
                            onChanged: _isPlaying ? null : (value) {
                              setState(() {
                                _playbackSpeed = value;
                              });
                            },
                          ),
                        ),
                        Text('${_playbackSpeed.toStringAsFixed(1)}x'),
                      ],
                    ),
                    
                    // Loop Toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Loop'),
                        Switch(
                          value: _loopPlayback,
                          onChanged: _isPlaying ? null : (value) {
                            setState(() {
                              _loopPlayback = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Play/Stop Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isPlaying ? null : _playSequence,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play Sequence'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isPlaying ? _stopSequence : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Positions List
          Expanded(
            child: _positions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gesture, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No positions saved yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Disable torque and move the arm\nthen save positions',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _positions.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final pos = _positions[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${index + 1}'),
                          ),
                          title: Text(pos.name),
                          subtitle: Text(
                            'Saved: ${_formatTime(pos.timestamp)}\n'
                            'Positions: ${pos.position.jointPositions.join(", ")}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deletePosition(index),
                          ),
                          onTap: () async {
                            // Load this position to the arm
                            final bleService = Provider.of<ArmBleService>(context, listen: false);
                            await bleService.setAllJoints(pos.position);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Moving to: ${pos.name}')),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }
}
