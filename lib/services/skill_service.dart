import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/logger.dart';
import '../models/skill.dart';

class SkillService {
  final Logger _log = Logger('SkillService');
  List<Skill> _skills = [];
  File? _file;

  List<Skill> get skills => List.unmodifiable(_skills);

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/ultron_skills.json');
      if (await _file!.exists()) {
        final data = await _file!.readAsString();
        if (data.isNotEmpty) {
          final list = jsonDecode(data) as List;
          _skills = list.map((e) => Skill.fromJson(e)).toList();
        }
      }
      _log.i('Skills loaded: ${_skills.length} skills');
    } catch (e) {
      _log.w('Skills init failed: $e');
      _skills = [];
    }
  }

  Future<void> _save() async {
    if (_file == null) return;
    try {
      final data = jsonEncode(_skills.map((e) => e.toJson()).toList());
      await _file!.writeAsString(data);
    } catch (e) {
      _log.e('Failed to save skills: $e');
    }
  }

  Skill? match(String userInput) {
    final lower = userInput.toLowerCase().trim();
    for (final skill in _skills) {
      for (final trigger in skill.triggers) {
        if (lower.contains(trigger.toLowerCase())) {
          skill.useCount++;
          _save();
          return skill;
        }
      }
    }
    return null;
  }

  Future<Skill> learn({
    required String name,
    required String description,
    required List<String> triggers,
    required String steps,
  }) async {
    final existing = _skills.indexWhere((s) => s.name.toLowerCase() == name.toLowerCase());
    final now = DateTime.now();
    final skill = Skill(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      triggers: triggers,
      steps: steps,
      createdAt: now,
    );
    if (existing >= 0) {
      _skills[existing] = skill;
    } else {
      _skills.add(skill);
    }
    await _save();
    _log.i('Skill learned: $name (${triggers.length} triggers)');
    return skill;
  }

  Future<bool> forget(String nameOrTrigger) async {
    final lower = nameOrTrigger.toLowerCase().trim();
    final before = _skills.length;
    _skills.removeWhere((s) =>
      s.name.toLowerCase() == lower ||
      s.triggers.any((t) => t.toLowerCase().contains(lower)));
    if (_skills.length != before) {
      await _save();
      _log.i('Forgot ${before - _skills.length} skill(s) matching "$nameOrTrigger"');
      return true;
    }
    return false;
  }

  List<Skill> search(String query) {
    final lower = query.toLowerCase();
    return _skills.where((s) =>
      s.name.toLowerCase().contains(lower) ||
      s.description.toLowerCase().contains(lower) ||
      s.triggers.any((t) => t.toLowerCase().contains(lower))
    ).toList();
  }
}
