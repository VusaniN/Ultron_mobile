import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../core/logger.dart';

class VoiceService {
  final Logger _log = Logger('VoiceService');
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _isSpeechAvailable = false;
  String? _localeId;
  List<LocaleName> _availableLocales = [];
  bool _cloudTtsFailed = false;
  bool _piperAvailable = false;
  String? _piperPath;
  String? _piperModelPath;
  String _wakeWord = '';
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;
  static const Duration _speakCooldown = Duration(milliseconds: 500);

  Duration _listenDuration = const Duration(seconds: 120);
  Duration _pauseDuration = const Duration(seconds: 8);
  ListenMode _listenMode = ListenMode.dictation;

  String get wakeWord => _wakeWord;
  Duration get listenDuration => _listenDuration;
  Duration get pauseDuration => _pauseDuration;
  ListenMode get listenMode => _listenMode;
  List<LocaleName> get availableLocales => _availableLocales;
  String? get currentLocale => _localeId;
  bool get isListening => _speech.isListening;
  bool get isSpeechAvailable => _isSpeechAvailable;

  void setListenDuration(Duration d) => _listenDuration = d;
  void setPauseDuration(Duration d) => _pauseDuration = d;
  void setListenMode(ListenMode m) => _listenMode = m;
  void setLocale(String? localeId) => _localeId = localeId;

  Future<bool> init() async {
    _wakeWord = dotenv.env['WAKE_WORD']?.trim().toLowerCase() ?? 'ultron';

    try {
      _isSpeechAvailable = await _speech.initialize(
        onError: (error) => _log.w('Speech error: $error'),
        onStatus: (status) => _log.d('Speech status: $status'),
      );
      if (_isSpeechAvailable) {
        _availableLocales = await _speech.locales();
        _log.d('Available locales: ${_availableLocales.map((l) => l.localeId).toList()}');
        final en = _availableLocales.firstWhere(
          (l) => l.localeId.startsWith('en'),
          orElse: () => _availableLocales.first,
        );
        _localeId = en.localeId;
        _log.i('Speech initialized, locale: $_localeId');
      }
    } catch (e) {
      _log.w('Speech init failed: $e');
      _isSpeechAvailable = false;
    }

    await _initPiper();

    try {
      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.42);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      final voices = await _tts.getVoices;
      if (voices != null && voices.isNotEmpty) {
        _log.i('Available TTS voices: $voices');
        String? preferredName;
        for (final v in voices) {
          if (v is Map) {
            final name = v['name']?.toString() ?? '';
            final locale = v['locale']?.toString() ?? '';
            _log.d('TTS voice: $name ($locale)');
            if (preferredName == null) preferredName = name;
            if (name.contains('George') || name.contains('Hazel') || name.contains('Susan')) {
              preferredName = name;
              break;
            }
          }
        }
        if (preferredName != null) {
          await _tts.setVoice({'name': preferredName});
          _log.i('Selected TTS voice: $preferredName');
        }
      }
    } catch (e) {
      _log.w('TTS init failed: $e');
    }
    return _isSpeechAvailable;
  }

  Future<void> _initPiper() async {
    try {
      final enabled = dotenv.env['PIPER_ENABLED'] == 'true';
      if (!enabled) {
        _log.d('Piper disabled in .env');
        return;
      }

      _piperPath = dotenv.env['PIPER_PATH'];
      _piperModelPath = dotenv.env['PIPER_MODEL'];

      if (_piperPath == null || _piperModelPath == null) {
        _log.d('Piper path or model not configured');
        return;
      }

      if (await File(_piperPath!).exists() && await File(_piperModelPath!).exists()) {
        _piperAvailable = true;
        _log.i('Piper TTS available');
      } else {
        _log.w('Piper files not found: $_piperPath or $_piperModelPath');
      }
    } catch (e) {
      _log.w('Piper init failed: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    _isSpeaking = false;
    _log.d('Speaking stopped');
  }

  Future<void> speak(String text) async {
    _isSpeaking = true;
    try {
      if (!_cloudTtsFailed) {
        try {
          if (!_isSpeaking) return;
          await _speakEleven(text);
          return;
        } catch (e) {
          _log.w('ElevenLabs failed: $e');
          _cloudTtsFailed = true;
        }
      }

      if (_piperAvailable) {
        try {
          if (!_isSpeaking) return;
          await _speakPiper(text);
          return;
        } catch (e) {
          _log.w('Piper failed: $e');
          _piperAvailable = false;
        }
      }

      if (!_isSpeaking) return;
      await _tts.speak(text);
    } finally {
      _isSpeaking = false;
      await Future.delayed(_speakCooldown);
    }
  }

  Future<void> _speakPiper(String text) async {
    final dir = await getTemporaryDirectory();
    final dirPath = dir.path.replaceAll('\\', '/');
    final outputPath = '$dirPath/ultron_piper_output.wav';
    final piperDir = File(_piperPath!).parent.path;

    final configPath = dotenv.env['PIPER_CONFIG'];
    final args = ['--model', _piperModelPath!, '--output-file', outputPath];
    if (configPath != null && await File(configPath).exists()) {
      args.addAll(['--config', configPath]);
    }
    args.add('--debug');

    final process = await Process.start(
      _piperPath!,
      args,
      workingDirectory: piperDir,
    );

    process.stdin.writeln(text);
    await process.stdin.close();

    final errors = await process.stderr.transform(utf8.decoder).join();
    final result = await process.exitCode;

    if (result != 0) {
      _log.e('Piper error (exit $result): $errors');
      if (await File(outputPath).exists()) {
        try { await File(outputPath).delete(); } catch (_) {}
      }
      throw Exception('Piper exit code $result: $errors');
    }

    final outFile = File(outputPath);
    if (!await outFile.exists()) {
      throw Exception('Piper did not produce output file');
    }

    await _player.play(DeviceFileSource(outputPath));
  }

  Future<void> _speakEleven(String text) async {
    final apiKey = dotenv.env['ELEVENLABS_API_KEY'];
    final voiceId = dotenv.env['ELEVENLABS_VOICE_ID'] ?? '21m00Tcm4TlvDq8ikWAM';
    if (apiKey == null || apiKey.isEmpty || apiKey == 'your_key_here') {
      throw Exception('No ElevenLabs API key');
    }

    final res = await http.post(
      Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId'),
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': text,
        'model_id': 'eleven_multilingual_v2',
        'voice_settings': {
          'stability': 0.5,
          'similarity_boost': 0.75,
        },
      }),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('ElevenLabs returned ${res.statusCode}');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ultron_eleven.mp3');
    await file.writeAsBytes(res.bodyBytes);
    await _player.play(DeviceFileSource(file.path));
  }

  Future<String?> listen({required Function(String) onResult}) async {
    await stopSpeaking();
    if (!_isSpeechAvailable) {
      await init();
    }
    if (!_isSpeechAvailable) return "Error: Speech not available";

    final completer = Completer<String?>();

    try {
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords;
          if (text.isNotEmpty) {
            onResult(text);
          }
          if (result.finalResult) {
            if (!completer.isCompleted) {
              completer.complete(text.isNotEmpty ? text : null);
            }
          }
        },
        listenFor: _listenDuration,
        pauseFor: _pauseDuration,
        localeId: _localeId,
        partialResults: true,
        cancelOnError: true,
        listenMode: _listenMode,
      );
    } catch (e) {
      _log.e('Listen failed: $e');
      if (!completer.isCompleted) completer.complete(null);
      return null;
    }

    return completer.future;
  }

  void stopListening() {
    if (_speech.isListening) {
      _speech.stop();
      _log.d('Speech stopped');
    }
  }

  Future<String?> listenForWakeWord({required Function(String) onPartial}) async {
    await stopSpeaking();
    if (!_isSpeechAvailable) {
      await init();
    }
    if (!_isSpeechAvailable) return null;

    final completer = Completer<String?>();
    String fullText = '';

    try {
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords.trim().toLowerCase();
          if (text.isNotEmpty) {
            fullText = result.recognizedWords;
            onPartial(fullText);
            if (text.contains(_wakeWord)) {
              _speech.stop();
              if (!completer.isCompleted) {
                completer.complete(result.recognizedWords);
              }
            }
          }
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(result.recognizedWords.isNotEmpty ? result.recognizedWords : null);
          }
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: _pauseDuration,
        localeId: _localeId,
        partialResults: false,
        cancelOnError: true,
        listenMode: _listenMode,
      );
    } catch (e) {
      _log.e('Wake word listen failed: $e');
      if (!completer.isCompleted) completer.complete(null);
      return null;
    }

    return completer.future;
  }

  void cancelPendingListen() {
    if (!_speech.isListening) return;
    _log.d('Cancelling pending listen');
    _speech.stop();
  }
}
