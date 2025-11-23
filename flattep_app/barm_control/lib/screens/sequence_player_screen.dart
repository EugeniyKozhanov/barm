import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/arm_ble_service.dart';

class SequencePlayerScreen extends StatefulWidget {
  const SequencePlayerScreen({super.key});

  @override
  State<SequencePlayerScreen> createState() => _SequencePlayerScreenState();
}

class _SequencePlayerScreenState extends State<SequencePlayerScreen> {
  int _startSlot = 0;
  int _endSlot = 3;
  double _delayMs = 2000.0;
  bool _loop = false;
  bool _isPlaying = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sequence Player'),
      ),
      body: Consumer<ArmBleService>(
        builder: (context, bleService, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoCard(),
                const SizedBox(height: 16),
                _buildSequenceSettingsCard(),
                const SizedBox(height: 16),
                _buildControlButtons(bleService),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Sequence Playback',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Play a sequence of saved positions in order. '
              'The robot will move from the start slot to the end slot with the specified delay between positions.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSequenceSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sequence Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Start Slot
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Start Slot:', style: TextStyle(fontSize: 16)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _startSlot > 0
                          ? () => setState(() {
                                _startSlot--;
                                if (_startSlot > _endSlot) _endSlot = _startSlot;
                              })
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _startSlot.toString(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _startSlot < 15
                          ? () => setState(() {
                                _startSlot++;
                                if (_startSlot > _endSlot) _endSlot = _startSlot;
                              })
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            
            const Divider(),
            
            // End Slot
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('End Slot:', style: TextStyle(fontSize: 16)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _endSlot > _startSlot
                          ? () => setState(() => _endSlot--)
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _endSlot.toString(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _endSlot < 15
                          ? () => setState(() => _endSlot++)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            
            const Divider(),
            
            // Delay
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delay between positions: ${_delayMs.toInt()} ms'),
                Slider(
                  value: _delayMs,
                  min: 500,
                  max: 10000,
                  divisions: 95,
                  label: '${_delayMs.toInt()} ms',
                  onChanged: (value) => setState(() => _delayMs = value),
                ),
              ],
            ),
            
            const Divider(),
            
            // Loop
            SwitchListTile(
              title: const Text('Loop Sequence'),
              subtitle: const Text('Repeat the sequence continuously'),
              value: _loop,
              onChanged: (value) => setState(() => _loop = value),
            ),
            
            const SizedBox(height: 8),
            
            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Summary:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('• Will play positions from slot $_startSlot to $_endSlot'),
                  Text('• Total positions: ${_endSlot - _startSlot + 1}'),
                  Text('• Delay: ${_delayMs.toInt()} ms between positions'),
                  Text('• Mode: ${_loop ? "Loop continuously" : "Play once"}'),
                ],
              ),
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
            if (!_isPlaying)
              ElevatedButton.icon(
                onPressed: bleService.isConnected
                    ? () => _playSequence(bleService)
                    : null,
                icon: const Icon(Icons.play_arrow, size: 32),
                label: const Text('Start Sequence', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 60),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: bleService.isConnected
                    ? () => _stopSequence(bleService)
                    : null,
                icon: const Icon(Icons.stop, size: 32),
                label: const Text('Stop Sequence', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 60),
                ),
              ),
            
            if (!bleService.isConnected)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Please connect to ARM100 first',
                  style: TextStyle(color: Colors.orange.shade700),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _playSequence(ArmBleService bleService) async {
    setState(() => _isPlaying = true);
    
    final success = await bleService.playSequence(
      _startSlot,
      _endSlot,
      _delayMs.toInt(),
      _loop,
    );
    
    if (!success && mounted) {
      setState(() => _isPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start sequence')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loop
              ? 'Sequence started (looping)'
              : 'Sequence started'),
        ),
      );
    }
  }
  
  Future<void> _stopSequence(ArmBleService bleService) async {
    final success = await bleService.stopSequence();
    
    setState(() => _isPlaying = false);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sequence stopped')),
      );
    }
  }
}
