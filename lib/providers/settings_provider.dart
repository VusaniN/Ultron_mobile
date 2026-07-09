import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/logger.dart';
import '../core/secure_storage.dart';

class SettingsProvider extends ChangeNotifier {
  final Logger _log = Logger('SettingsProvider');
  final SecureStorage _secure = SecureStorage();

  String _currentModelId = 'qwen/qwen3-coder:free';
  String _wakeWord = 'ultron';
  String _voiceId = '21m00Tcm4TlvDq8ikWAM';
  bool _piperEnabled = true;
  bool _cloudTts = true;
  bool _debugMode = false;
  bool _pushToTalk = true;
  bool _showThoughts = true;
  String _personaId = 'ultron_default';

  String get currentModelId => _currentModelId;
  String get wakeWord => _wakeWord;
  String get voiceId => _voiceId;
  bool get piperEnabled => _piperEnabled;
  bool get cloudTts => _cloudTts;
  bool get debugMode => _debugMode;
  bool get pushToTalk => _pushToTalk;
  bool get showThoughts => _showThoughts;
  String get personaId => _personaId;

  void setModelId(String id) {
    _currentModelId = id;
    notifyListeners();
  }

  Future<void> setWakeWord(String word) async {
    _wakeWord = word;
    await _secure.write('WAKE_WORD', word);
    notifyListeners();
  }

  Future<void> setVoiceId(String id) async {
    _voiceId = id;
    await _secure.write('ELEVENLABS_VOICE_ID', id);
    notifyListeners();
  }

  void setPushToTalk(bool v) {
    _pushToTalk = v;
    notifyListeners();
  }

  void setShowThoughts(bool v) {
    _showThoughts = v;
    notifyListeners();
  }

  void setPersonaId(String id) {
    _personaId = id;
    notifyListeners();
  }

  void togglePiper() {
    _piperEnabled = !_piperEnabled;
    notifyListeners();
  }

  void toggleCloudTts() {
    _cloudTts = !_cloudTts;
    notifyListeners();
  }

  void toggleDebugMode() {
    _debugMode = !_debugMode;
    notifyListeners();
  }

  Future<String> get _settingsPath async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/ultron_settings.json';
  }

  Future<void> save() async {
    try {
      final path = await _settingsPath;
      final data = jsonEncode({
        'currentModelId': _currentModelId,
        'wakeWord': _wakeWord,
        'voiceId': _voiceId,
        'piperEnabled': _piperEnabled,
        'cloudTts': _cloudTts,
        'debugMode': _debugMode,
        'pushToTalk': _pushToTalk,
        'showThoughts': _showThoughts,
        'personaId': _personaId,
      });
      await File(path).writeAsString(data);
    } catch (e) {
      _log.w('Failed to save settings: $e');
    }
  }

  Future<void> load() async {
    try {
      final path = await _settingsPath;
      final file = File(path);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _currentModelId = data['currentModelId'] as String? ?? _currentModelId;
      _wakeWord = data['wakeWord'] as String? ?? _wakeWord;
      _voiceId = data['voiceId'] as String? ?? _voiceId;
      _piperEnabled = data['piperEnabled'] as bool? ?? _piperEnabled;
      _cloudTts = data['cloudTts'] as bool? ?? _cloudTts;
      _debugMode = data['debugMode'] as bool? ?? _debugMode;
      _pushToTalk = data['pushToTalk'] as bool? ?? _pushToTalk;
      _showThoughts = data['showThoughts'] as bool? ?? _showThoughts;
      _personaId = data['personaId'] as String? ?? _personaId;
      _log.i('Settings loaded from $path');
    } catch (e) {
      _log.w('Failed to load settings: $e');
    }
  }
}
