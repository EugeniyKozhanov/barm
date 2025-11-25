import 'dart:typed_data';
import 'dart:convert';

class ArmPosition {
  final List<int> jointPositions; // 6 joints, values 0-4095
  
  static const int numJoints = 6;
  static const int minPosition = 0;
  static const int maxPosition = 4095;
  static const int centerPosition = 2048;
  
  ArmPosition(this.jointPositions) {
    assert(jointPositions.length == numJoints);
    for (var pos in jointPositions) {
      assert(pos >= minPosition && pos <= maxPosition);
    }
  }
  
  factory ArmPosition.center() {
    return ArmPosition(List.filled(numJoints, centerPosition));
  }
  
  factory ArmPosition.fromBytes(Uint8List bytes) {
    assert(bytes.length >= numJoints * 2);
    final positions = <int>[];
    for (int i = 0; i < numJoints; i++) {
      final low = bytes[i * 2];
      final high = bytes[i * 2 + 1];
      positions.add((high << 8) | low);
    }
    return ArmPosition(positions);
  }
  
  Uint8List toBytes() {
    final bytes = Uint8List(numJoints * 2);
    for (int i = 0; i < numJoints; i++) {
      bytes[i * 2] = jointPositions[i] & 0xFF;
      bytes[i * 2 + 1] = (jointPositions[i] >> 8) & 0xFF;
    }
    return bytes;
  }
  
  ArmPosition copyWith({List<int>? jointPositions}) {
    return ArmPosition(jointPositions ?? List.from(this.jointPositions));
  }
  
  @override
  String toString() {
    return 'ArmPosition(${jointPositions.map((p) => p.toString()).join(', ')})';
  }
}

class SavedPosition {
  final int slot;
  final ArmPosition position;
  final String? name;
  
  SavedPosition({
    required this.slot,
    required this.position,
    this.name,
  }) : assert(slot >= 0 && slot < 16);
  
  String get displayName => name ?? 'Position $slot';
  
  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'slot': slot,
      'position': position.jointPositions,
      'name': name,
    };
  }
  
  // Create from JSON
  factory SavedPosition.fromJson(Map<String, dynamic> json) {
    return SavedPosition(
      slot: json['slot'] as int,
      position: ArmPosition(List<int>.from(json['position'] as List)),
      name: json['name'] as String?,
    );
  }
  
  // Serialize list of saved positions to JSON string
  static String savedPositionsToJsonString(List<SavedPosition?> positions) {
    final validPositions = positions
        .where((p) => p != null)
        .map((p) => p!.toJson())
        .toList();
    return jsonEncode(validPositions);
  }
  
  // Deserialize JSON string to list of saved positions (16 slots)
  static List<SavedPosition?> savedPositionsFromJsonString(String jsonString) {
    final List<SavedPosition?> result = List.filled(16, null);
    try {
      final List<dynamic> list = jsonDecode(jsonString) as List;
      for (var json in list) {
        final position = SavedPosition.fromJson(json as Map<String, dynamic>);
        if (position.slot >= 0 && position.slot < 16) {
          result[position.slot] = position;
        }
      }
    } catch (e) {
      print('Error parsing saved positions: $e');
    }
    return result;
  }
}
