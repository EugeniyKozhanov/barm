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
  List<TeachingSession> _sessions = [];
  TeachingSession? _currentSession;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  bool _loopPlayback = false;
  final _uuid = const Uuid();
  
  @override
  void initState() {
    super.initState();
    _loadSessions();
  }
  
  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('teaching_sessions');
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final sessionList = TeachingSessionList.fromJsonString(jsonString);
        setState(() {
          _sessions = sessionList.sessions;
          // Load the most recently updated session as current
          if (_sessions.isNotEmpty) {
            _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            _currentSession = _sessions.first;
          }
        });
      } catch (e) {
        debugPrint('Error loading teaching sessions: $e');
      }
    }
  }
  
  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionList = TeachingSessionList(_sessions);
    await prefs.setString('teaching_sessions', sessionList.toJsonString());
  }
  
  List<TeachingPosition> get _positions => _currentSession?.positions ?? [];
  
  Future<void> _saveCurrentSession() async {
    if (_currentSession != null) {
      // Update the session in the list
      final index = _sessions.indexWhere((s) => s.id == _currentSession!.id);
      if (index != -1) {
        _sessions[index] = _currentSession!.copyWith(updatedAt: DateTime.now());
      }
      await _saveSessions();
    }
  }
  
  Future<void> _createNewSession() async {
    final TextEditingController nameController = TextEditingController(
      text: 'Session ${_sessions.length + 1}',
    );
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Session'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Session Name',
            hintText: 'Enter a name for this session',
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    
    if (name != null && name.isNotEmpty) {
      final newSession = TeachingSession(
        id: _uuid.v4(),
        name: name,
        positions: [],
      );
      
      setState(() {
        _sessions.add(newSession);
        _currentSession = newSession;
      });
      
      await _saveSessions();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created session: $name')),
      );
    }
  }
  
  Future<void> _selectSession() async {
    if (_sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sessions available')),
      );
      return;
    }
    
    final selected = await showDialog<TeachingSession>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Session'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _sessions.length,
            itemBuilder: (context, index) {
              final session = _sessions[index];
              return ListTile(
                title: Text(session.name),
                subtitle: Text('${session.positions.length} positions'),
                selected: session.id == _currentSession?.id,
                onTap: () => Navigator.pop(context, session),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (selected != null) {
      setState(() {
        _currentSession = selected;
      });
    }
  }
  
  Future<void> _deleteSession(TeachingSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text('Delete session "${session.name}" and all its positions?'),
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
        _sessions.remove(session);
        if (_currentSession?.id == session.id) {
          _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
        }
      });
      await _saveSessions();
    }
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
      
      if (_currentSession == null) {
        // Create default session if none exists
        _currentSession = TeachingSession(
          id: _uuid.v4(),
          name: 'Default Session',
          positions: [],
        );
        _sessions.add(_currentSession!);
      }
      
      setState(() {
        _currentSession = _currentSession!.copyWith(
          positions: [..._currentSession!.positions, teachingPos],
        );
      });
      
      await _saveCurrentSession();
      
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
    
    if (confirmed == true && _currentSession != null) {
      final updatedPositions = List<TeachingPosition>.from(_currentSession!.positions);
      updatedPositions.removeAt(index);
      
      setState(() {
        _currentSession = _currentSession!.copyWith(positions: updatedPositions);
      });
      await _saveCurrentSession();
    }
  }
  
  Future<void> _clearAll() async {
    if (_currentSession == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: const Text('Delete all positions in current session?'),
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
        _currentSession = _currentSession!.copyWith(positions: []);
      });
      await _saveCurrentSession();
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
        title: Text(_currentSession != null ? _currentSession!.name : 'Teaching Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _selectSession,
            tooltip: 'Select session',
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            onPressed: _createNewSession,
            tooltip: 'New session',
          ),
          if (_currentSession != null && _sessions.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: () => _deleteSession(_currentSession!),
              tooltip: 'Delete session',
            ),
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
          // Session info card
          if (_currentSession != null)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Session: ${_currentSession!.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            '${_positions.length} positions',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
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
            child: _currentSession == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No session selected',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a new session or select an existing one',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _createNewSession,
                          icon: const Icon(Icons.create_new_folder),
                          label: const Text('Create New Session'),
                        ),
                      ],
                    ),
                  )
                : _positions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.gesture, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No positions in this session',
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
