import 'dart:convert';
import 'arm_position.dart';

class TeachingPosition {
  final String id;
  final String name;
  final ArmPosition position;
  final DateTime timestamp;
  final int delayAfterMs; // Delay after reaching this position
  
  TeachingPosition({
    required this.id,
    required this.name,
    required this.position,
    required this.timestamp,
    this.delayAfterMs = 1000,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position.jointPositions,
      'timestamp': timestamp.toIso8601String(),
      'delayAfterMs': delayAfterMs,
    };
  }
  
  factory TeachingPosition.fromJson(Map<String, dynamic> json) {
    return TeachingPosition(
      id: json['id'],
      name: json['name'],
      position: ArmPosition(List<int>.from(json['position'])),
      timestamp: DateTime.parse(json['timestamp']),
      delayAfterMs: json['delayAfterMs'] ?? 1000,
    );
  }
}

class TeachingSession {
  final List<TeachingPosition> positions;
  
  TeachingSession(this.positions);
  
  String toJsonString() {
    final list = positions.map((p) => p.toJson()).toList();
    return jsonEncode(list);
  }
  
  factory TeachingSession.fromJsonString(String jsonString) {
    final List<dynamic> list = jsonDecode(jsonString);
    final positions = list.map((json) => TeachingPosition.fromJson(json)).toList();
    return TeachingSession(positions);
  }
}
