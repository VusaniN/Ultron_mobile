import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'logger.dart';

class SecureStorage {
  static final SecureStorage _instance = SecureStorage._();
  factory SecureStorage() => _instance;
  SecureStorage._();

  final Logger _log = Logger('SecureStorage');
  bool _initialized = false;
  File? _file;
  final Map<String, String> _cache = {};

  static const List<_CredentialKey> _knownKeys = [
    _CredentialKey('OPENROUTER_API_KEY'),
    _CredentialKey('GOOGLE_API_KEY'),
    _CredentialKey('ELEVENLABS_API_KEY'),
    _CredentialKey('WAKE_WORD'),
    _CredentialKey('OPENROUTER_MODEL'),
    _CredentialKey('ELEVENLABS_VOICE_ID'),
  ];

  static const String _keyPrefix = '_ultron_';

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/ultron_credentials.dat');
      if (await _file!.exists()) {
        final data = await _file!.readAsString();
        if (data.isNotEmpty) {
          try {
            final decoded = _decode(data);
            _cache.addAll(decoded);
          } catch (e) {
            _log.w('Failed to decode credentials file: $e');
          }
        }
      }
      await _migrateFromDotenv();
      _initialized = true;
      _log.i('Secure storage initialized');
    } catch (e) {
      _log.w('Secure storage init failed, falling back to env: $e');
    }
  }

  Future<void> _migrateFromDotenv() async {
    bool changed = false;
    for (final key in _knownKeys) {
      if (_cache.containsKey(key.envKey)) continue;
      final envValue = dotenv.env[key.envKey];
      if (envValue != null && envValue.isNotEmpty && !envValue.contains('your_')) {
        _cache[key.envKey] = envValue;
        changed = true;
        _log.i('Migrated ${key.envKey} from .env');
      }
    }
    if (changed) await _persist();
  }

  Future<String?> read(String envKey) async {
    if (_cache.containsKey(envKey)) return _cache[envKey];
    final envVal = dotenv.env[envKey];
    if (envVal != null && envVal.isNotEmpty && !envVal.contains('your_')) return envVal;
    return null;
  }

  Future<void> write(String envKey, String value) async {
    _cache[envKey] = value;
    await _persist();
    _log.i('Updated $envKey');
  }

  Future<void> delete(String envKey) async {
    _cache.remove(envKey);
    await _persist();
  }

  Future<void> _persist() async {
    if (_file == null) return;
    try {
      final encoded = _encode(_cache);
      await _file!.writeAsString(encoded);
    } catch (e) {
      _log.e('Failed to persist credentials: $e');
    }
  }

  String _encode(Map<String, String> data) {
    final json = jsonEncode(data);
    final bytes = utf8.encode(json);
    final key = _deriveKey();
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = (bytes[i] ^ key[i % key.length]).toInt();
    }
    return base64Encode(bytes);
  }

  Map<String, String> _decode(String encoded) {
    final bytes = base64Decode(encoded);
    final key = _deriveKey();
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = (bytes[i] ^ key[i % key.length]).toInt();
    }
    final json = utf8.decode(bytes);
    return Map<String, String>.from(jsonDecode(json));
  }

  List<int> _deriveKey() {
    final base = _keyPrefix.codeUnits;
    final repeated = <int>[];
    while (repeated.length < 64) {
      repeated.addAll(base);
    }
    return repeated.take(64).toList();
  }
}

class _CredentialKey {
  final String envKey;
  const _CredentialKey(this.envKey);
}
