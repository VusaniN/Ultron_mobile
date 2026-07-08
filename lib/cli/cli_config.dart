import 'dart:convert';
import 'dart:io';
import '../core/logger.dart';

class CliConfig {
  final Logger _log = Logger('CliConfig');

  String openRouterKey = '';
  String googleApiKey = '';
  String elevenLabsKey = '';
  String wakeWord = 'ultron';

  Future<void> load() async {
    final env = Platform.environment;
    openRouterKey = env['OPENROUTER_API_KEY'] ?? '';
    googleApiKey = env['GOOGLE_API_KEY'] ?? '';
    elevenLabsKey = env['ELEVENLABS_API_KEY'] ?? '';
    wakeWord = env['WAKE_WORD']?.toLowerCase() ?? 'ultron';

    final configDir = Directory('${_homeDir}/.ultron');
    final configFile = File('${configDir.path}/config.json');
    if (await configFile.exists()) {
      try {
        final data = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
        openRouterKey = data['openrouter_key'] as String? ?? openRouterKey;
        googleApiKey = data['google_api_key'] as String? ?? googleApiKey;
        elevenLabsKey = data['elevenlabs_key'] as String? ?? elevenLabsKey;
        wakeWord = data['wake_word'] as String? ?? wakeWord;
        _log.i('Loaded config from ${configFile.path}');
      } catch (e) {
        _log.w('Failed to read config file: $e');
      }
    }

    if (openRouterKey.isEmpty) {
      _log.w('OPENROUTER_API_KEY not set — LLM calls will fail');
    }
    if (googleApiKey.isEmpty) {
      _log.d('GOOGLE_API_KEY not set — Gemini unavailable');
    }
  }

  Future<void> save() async {
    try {
      final configDir = Directory('${_homeDir}/.ultron');
      if (!await configDir.exists()) await configDir.create(recursive: true);
      final configFile = File('${configDir.path}/config.json');
      await configFile.writeAsString(jsonEncode({
        'openrouter_key': openRouterKey,
        'google_api_key': googleApiKey,
        'elevenlabs_key': elevenLabsKey,
        'wake_word': wakeWord,
      }));
      await configFile.setUnixMode(0o600);
      _log.i('Config saved to ${configFile.path}');
    } catch (e) {
      _log.w('Failed to save config: $e');
    }
  }

  String get _homeDir {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '.';
    }
    return Platform.environment['HOME'] ?? '.';
  }
}

extension UnixPerms on File {
  Future<void> setUnixMode(int mode) async {
    if (!Platform.isWindows) {
      await Process.run('chmod', [mode.toRadixString(8), path]);
    }
  }
}
