import 'dart:typed_data';

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
}
