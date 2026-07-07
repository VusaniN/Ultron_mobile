import 'dart:convert';

class Skill {
  final String id;
  final String name;
  final String description;
  final List<String> triggers;
  final String steps;
  final DateTime createdAt;
  int useCount;

  Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.triggers,
    required this.steps,
    required this.createdAt,
    this.useCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'triggers': triggers,
    'steps': steps,
    'createdAt': createdAt.toIso8601String(),
    'useCount': useCount,
  };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    triggers: (json['triggers'] as List).cast<String>(),
    steps: json['steps'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    useCount: json['useCount'] as int? ?? 0,
  );
}
