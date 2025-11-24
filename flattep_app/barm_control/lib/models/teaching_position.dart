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
  final String id;
  final String name;
  final List<TeachingPosition> positions;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  TeachingSession({
    required this.id,
    required this.name,
    required this.positions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  
  TeachingSession copyWith({
    String? name,
    List<TeachingPosition>? positions,
    DateTime? updatedAt,
  }) {
    return TeachingSession(
      id: id,
      name: name ?? this.name,
      positions: positions ?? this.positions,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'positions': positions.map((p) => p.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
  
  factory TeachingSession.fromJson(Map<String, dynamic> json) {
    return TeachingSession(
      id: json['id'],
      name: json['name'],
      positions: (json['positions'] as List).map((p) => TeachingPosition.fromJson(p)).toList(),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
  
  String toJsonString() {
    return jsonEncode(toJson());
  }
  
  factory TeachingSession.fromJsonString(String jsonString) {
    return TeachingSession.fromJson(jsonDecode(jsonString));
  }
}

class TeachingSessionList {
  final List<TeachingSession> sessions;
  
  TeachingSessionList(this.sessions);
  
  String toJsonString() {
    final list = sessions.map((s) => s.toJson()).toList();
    return jsonEncode(list);
  }
  
  factory TeachingSessionList.fromJsonString(String jsonString) {
    final List<dynamic> list = jsonDecode(jsonString);
    final sessions = list.map((json) => TeachingSession.fromJson(json)).toList();
    return TeachingSessionList(sessions);
  }
}
