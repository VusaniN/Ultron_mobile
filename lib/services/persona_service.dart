import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/persona.dart';
import '../core/logger.dart';

class PersonaService {
  final Logger _log = Logger('PersonaService');
  Persona _current = Persona.defaultPersona;
  List<Persona> _customPersonas = [];
  File? _file;

  Persona get current => _current;
  List<Persona> get allPersonas => [...Persona.builtIn, ..._customPersonas];

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/ultron_personas.json');
      if (await _file!.exists()) {
        final data = await _file!.readAsString();
        if (data.isNotEmpty) {
          final list = jsonDecode(data) as List;
          _customPersonas = list.map((e) => _fromJson(e)).toList();
        }
      }
      _log.i('Persona service initialized, ${_customPersonas.length} custom personas');
    } catch (e) {
      _log.w('Failed to load custom personas: $e');
    }
  }

  Future<void> switchPersona(String id) async {
    final found = allPersonas.where((p) => p.id == id);
    if (found.isNotEmpty) {
      _current = found.first;
      _log.i('Switched to persona: ${_current.name}');
    }
  }

  Future<void> addCustom(Persona persona) async {
    _customPersonas.add(persona);
    await _save();
    _log.i('Added custom persona: ${persona.name}');
  }

  Future<void> removeCustom(String id) async {
    _customPersonas.removeWhere((p) => p.id == id);
    await _save();
    if (_current.id == id) {
      _current = Persona.defaultPersona;
    }
  }

  Future<void> _save() async {
    if (_file == null) return;
    try {
      final data = jsonEncode(_customPersonas.map((p) => _toJson(p)).toList());
      await _file!.writeAsString(data);
    } catch (e) {
      _log.e('Failed to save personas: $e');
    }
  }

  Map<String, dynamic> _toJson(Persona p) => {
    'id': p.id,
    'name': p.name,
    'description': p.description,
    'systemPromptAddon': p.systemPromptAddon,
    'config': p.config,
  };

  Persona _fromJson(Map<String, dynamic> json) => Persona(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    systemPromptAddon: json['systemPromptAddon'] as String? ?? '',
    config: (json['config'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v as String),
    ) ?? {},
  );
}
