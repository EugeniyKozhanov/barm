import 'dart:async';
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
    
    // If torque is disabled, temporarily enable it to read positions
    bool torqueWasDisabled = !_torqueEnabled;
    if (torqueWasDisabled) {
      debugPrint('Temporarily enabling torque to read positions...');
      
      // Create a completer to wait for position update
      final positionUpdateCompleter = Completer<void>();
      final oldPosition = bleService.currentPosition;
      
      // Listen for position changes
      void positionListener() {
        if (bleService.currentPosition != oldPosition && !positionUpdateCompleter.isCompleted) {
          debugPrint('Position updated after torque enable');
          positionUpdateCompleter.complete();
        }
      }
      bleService.addListener(positionListener);
      
      final success = await bleService.setTorque(true);
      if (!success) {
        bleService.removeListener(positionListener);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to enable torque for reading')),
        );
        return;
      }
      
      // Wait for position update or timeout after 1 second
      try {
        await positionUpdateCompleter.future.timeout(const Duration(seconds: 1));
        debugPrint('Received position update from ESP32');
      } catch (e) {
        debugPrint('Warning: Timeout waiting for position update, using cached position');
      } finally {
        bleService.removeListener(positionListener);
      }
    }
    
    final position = bleService.currentPosition;
    debugPrint('Current position to save: ${position.jointPositions}');
    
    // Restore torque state if we changed it
    if (torqueWasDisabled) {
      debugPrint('Restoring torque disabled state...');
      await bleService.setTorque(false);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    // Show dialog to name the position
    final TextEditingController nameController = TextEditingController(
      text: 'Position ${_positions.length + 1}',
    );
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Position'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Position Name',
                hintText: 'Enter a name for this position',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text('Current positions:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              position.jointPositions.map((p) => p.toString()).join(', '),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
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
    
    // Enable torque before playing
    if (!_torqueEnabled) {
      debugPrint('Enabling torque for playback...');
      final success = await bleService.setTorque(true);
      if (success) {
        setState(() {
          _torqueEnabled = true;
        });
        // Wait a bit for torque to stabilize
        await Future.delayed(const Duration(milliseconds: 200));
      } else {
        setState(() {
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to enable torque')),
        );
        return;
      }
    }
    
    int playCount = 0;
    do {
      playCount++;
      debugPrint('Playing sequence (iteration $playCount)...');
      
      for (int i = 0; i < _positions.length; i++) {
        if (!_isPlaying) {
          debugPrint('Playback stopped by user');
          break;
        }
        
        final pos = _positions[i];
        debugPrint('Moving to position ${i + 1}/${_positions.length}: ${pos.name}');
        setState(() {}); // Trigger UI update to show current position
        
        // Calculate movement time based on playback speed
        // Slower speed = more time, faster speed = less time
        final moveTime = (1000 / _playbackSpeed).toInt().clamp(100, 5000);
        final moveSpeed = (1500 * _playbackSpeed).toInt().clamp(100, 4000);
        
        // Move to position
        final success = await bleService.setAllJoints(
          pos.position,
          speed: moveSpeed,
          time: moveTime,
        );
        
        if (!success) {
          debugPrint('Failed to send move command for position $i');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to move to: ${pos.name}')),
          );
          break;
        }
        
        // Wait for movement to complete plus user-defined delay
        final totalDelay = moveTime + (pos.delayAfterMs / _playbackSpeed).toInt();
        debugPrint('Waiting ${totalDelay}ms for movement completion');
        await Future.delayed(Duration(milliseconds: totalDelay));
      }
      
      if (!_isPlaying) break;
      
    } while (_loopPlayback && _isPlaying);
    
    debugPrint('Playback complete');
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
