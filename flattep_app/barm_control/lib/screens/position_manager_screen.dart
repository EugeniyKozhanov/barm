import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/arm_ble_service.dart';
import '../models/arm_position.dart';

class PositionManagerScreen extends StatefulWidget {
  final ArmPosition currentPosition;
  
  const PositionManagerScreen({
    super.key,
    required this.currentPosition,
  });

  @override
  State<PositionManagerScreen> createState() => _PositionManagerScreenState();
}

class _PositionManagerScreenState extends State<PositionManagerScreen> {
  final List<SavedPosition?> _savedPositions = List.filled(16, null);
  int? _selectedSlot;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Position Manager'),
      ),
      body: Consumer<ArmBleService>(
        builder: (context, bleService, child) {
          return Column(
            children: [
              _buildCurrentPositionCard(),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 16,
                  itemBuilder: (context, index) => _buildSlotCard(index, bleService),
                ),
              ),
              _buildActionButtons(bleService),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildCurrentPositionCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Position',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(6, (i) => Chip(
                label: Text('J${i + 1}: ${widget.currentPosition.jointPositions[i]}'),
              )),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSlotCard(int index, ArmBleService bleService) {
    final isSelected = _selectedSlot == index;
    final savedPosition = _savedPositions[index];
    
    return GestureDetector(
      onTap: () => setState(() => _selectedSlot = index),
      child: Card(
        color: isSelected
            ? Colors.blue.shade100
            : (savedPosition != null ? Colors.green.shade50 : Colors.grey.shade100),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Slot $index',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Icon(
                savedPosition != null ? Icons.bookmark : Icons.bookmark_border,
                color: savedPosition != null ? Colors.green : Colors.grey,
              ),
              if (savedPosition != null)
                Text(
                  savedPosition.displayName,
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildActionButtons(ArmBleService bleService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (_selectedSlot != null && bleService.isConnected)
                  ? () => _savePosition(bleService)
                  : null,
              icon: const Icon(Icons.save),
              label: const Text('Save to Slot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (_selectedSlot != null && 
                          _savedPositions[_selectedSlot!] != null && 
                          bleService.isConnected)
                  ? () => _loadPosition(bleService)
                  : null,
              icon: const Icon(Icons.download),
              label: const Text('Load from Slot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _savePosition(ArmBleService bleService) async {
    if (_selectedSlot == null) return;
    
    final nameController = TextEditingController();
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Position'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Position Name (optional)',
            hintText: 'Position ${_selectedSlot}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (shouldSave == true) {
      final success = await bleService.savePosition(_selectedSlot!, widget.currentPosition);
      
      if (success && mounted) {
        setState(() {
          _savedPositions[_selectedSlot!] = SavedPosition(
            slot: _selectedSlot!,
            position: widget.currentPosition,
            name: nameController.text.isEmpty ? null : nameController.text,
          );
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Position saved to slot $_selectedSlot')),
        );
      }
    }
  }
  
  Future<void> _loadPosition(ArmBleService bleService) async {
    if (_selectedSlot == null) return;
    
    final success = await bleService.loadPosition(_selectedSlot!, speed: 1000, time: 1000);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loading position from slot $_selectedSlot')),
      );
    }
  }
}
