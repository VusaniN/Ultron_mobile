import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import '../core/logger.dart';
import '../core/secure_storage.dart';
import '../core/token_estimator.dart';

class LLMResponse {
  final String text;
  final String modelUsed;
  final int tokensUsed;
  final bool fromStream;
  final Duration latency;

  const LLMResponse({
    required this.text,
    required this.modelUsed,
    this.tokensUsed = 0,
    this.fromStream = false,
    this.latency = Duration.zero,
  });
}

class ModelConfig {
  final String id;
  final String label;
  final bool isFree;
  final double costPer1kTokens;
  final int maxTokens;
  final double reliabilityScore;

  const ModelConfig({
    required this.id,
    required this.label,
    this.isFree = true,
    this.costPer1kTokens = 0,
    this.maxTokens = 4096,
    this.reliabilityScore = 0.9,
  });
}

class LLMService {
  final Logger _log = Logger('LLMService');
  final SecureStorage _secure = SecureStorage();
  final TokenEstimator _tokenEstimator = TokenEstimator();
  String _currentModelId = 'qwen/qwen3-coder:free';
  final List<String> _modelBlacklist = [];
  final Map<String, int> _modelFailures = {};
  static const int _maxFailuresBeforeBlacklist = 3;

  static const List<ModelConfig> availableModels = [
    ModelConfig(id: 'openai/gpt-4o-mini', label: 'GPT-4o Mini', isFree: false, costPer1kTokens: 0.0015, reliabilityScore: 0.99),
    ModelConfig(id: 'openai/gpt-4o', label: 'GPT-4o', isFree: false, costPer1kTokens: 0.005, reliabilityScore: 0.99),
    ModelConfig(id: 'openrouter/free', label: 'Auto: Best Free Model', isFree: true, reliabilityScore: 0.7),
    ModelConfig(id: 'google/gemini-2.5-flash', label: 'Gemini 2.5 Flash', isFree: true, reliabilityScore: 0.95),
    ModelConfig(id: 'google/gemini-2.5-pro', label: 'Gemini 2.5 Pro', isFree: false, costPer1kTokens: 0.0035, reliabilityScore: 0.95),
    ModelConfig(id: 'google/gemma-4-31b-it:free', label: 'Gemma 4 31B (free)', isFree: true, reliabilityScore: 0.85),
    ModelConfig(id: 'nvidia/nemotron-3-super-120b-a12b:free', label: 'Nemotron 3 Super (free)', isFree: true, maxTokens: 1000000, reliabilityScore: 0.75),
    ModelConfig(id: 'qwen/qwen3-coder:free', label: 'Qwen 3 Coder (free)', isFree: true, maxTokens: 1000000, reliabilityScore: 0.8),
    ModelConfig(id: 'meta-llama/llama-3.3-70b-instruct:free', label: 'Llama 3.3 70B (free)', isFree: true, reliabilityScore: 0.85),
  ];

  static const String _openRouterBase = 'https://openrouter.ai/api/v1';

  String get currentModelId => _currentModelId;
  String get currentModel => _currentModelId;
  bool get isGoogleModel => _currentModelId.startsWith('google/');
  String get geminiModelName => _currentModelId.replaceFirst('google/', '');
  String get apiUrl => '$_openRouterBase/chat/completions';
  Map<String, String> get extraHeaders => {
    'HTTP-Referer': 'https://ultron.app',
    'X-Title': 'Ultron Mobile',
  };

  Future<String> getApiKey(String envKey) async {
    final val = await _secure.read(envKey);
    return val ?? '';
  }

  Future<bool> hasValidKey() async {
    final envKey = isGoogleModel ? 'GOOGLE_API_KEY' : 'OPENROUTER_API_KEY';
    final key = await getApiKey(envKey);
    return key.isNotEmpty && !key.contains('your_');
  }

  void switchModel(String modelId) {
    if (!availableModels.any((m) => m.id == modelId)) return;
    if (_modelBlacklist.contains(modelId)) {
      final fallback = findFallbackModel();
      if (fallback != null) {
        _currentModelId = fallback;
        _log.i('Model $modelId blacklisted, switched to fallback $fallback');
      }
      return;
    }
    _currentModelId = modelId;
    _log.i('Switched model to $modelId');
  }

  void blacklistModel(String modelId) {
    if (!_modelBlacklist.contains(modelId)) {
      _modelBlacklist.add(modelId);
      _log.w('Blacklisted model: $modelId');
    }
  }

  void recordFailure(String modelId) {
    _modelFailures[modelId] = (_modelFailures[modelId] ?? 0) + 1;
    if (_modelFailures[modelId]! >= _maxFailuresBeforeBlacklist) {
      blacklistModel(modelId);
    }
  }

  String? findFallbackModel() {
    for (final m in availableModels) {
      if (m.id != _currentModelId && !_modelBlacklist.contains(m.id) && m.isFree) {
        return m.id;
      }
    }
    for (final m in availableModels) {
      if (m.id != _currentModelId && !_modelBlacklist.contains(m.id)) {
        return m.id;
      }
    }
    return null;
  }

  ModelConfig? getModelConfig(String id) {
    final match = availableModels.where((m) => m.id == id);
    return match.isNotEmpty ? match.first : null;
  }

  String suggestBestModel(String userText, int conversationTokenCount) {
    final available = availableModels
        .where((m) => !_modelBlacklist.contains(m.id))
        .toList();
    if (available.isEmpty) return availableModels.first.id;
    final cheap = available.where((m) => m.isFree).toList();
    final isSimple = userText.length < 50 && conversationTokenCount < 500;
    if (isSimple && cheap.isNotEmpty) {
      if (cheap.any((m) => m.id.contains('gemini-2.5-flash'))) return 'google/gemini-2.5-flash';
      return cheap.first.id;
    }
    final needsLongContext = conversationTokenCount > 4000;
    if (needsLongContext) {
      final longCtx = available.where((m) => m.maxTokens >= 100000).toList();
      if (longCtx.isNotEmpty) return longCtx.first.id;
    }
    return _currentModelId;
  }

  Future<LLMResponse> chat({
    required String systemPrompt,
    required List<Map<String, String>> messages,
    String? userText,
    bool allowStreaming = true,
    int maxTokens = 512,
  }) async {
    final text = userText ?? messages.lastOrNull?['content'] ?? '';
    final conversationTokens = _tokenEstimator.estimateMessages(messages);
    final modelId = suggestBestModel(text, conversationTokens);
    final originalModel = _currentModelId;
    if (modelId != _currentModelId) {
      _log.i('Cost-aware routing: $modelId chosen over $_currentModelId');
      switchModel(modelId);
    }
    try {
      final response = allowStreaming
          ? await _chatWithStreaming(systemPrompt, messages, text, maxTokens)
          : await _chatWithModel(systemPrompt, messages, text, maxTokens);
      recordFailure(currentModelId);
      if (modelId != originalModel) switchModel(originalModel);
      return response;
    } catch (e) {
      _log.e('Model $currentModelId failed: $e');
      recordFailure(currentModelId);
      final fallback = findFallbackModel();
      if (fallback != null && fallback != currentModelId) {
        _log.i('Failing over to $fallback');
        switchModel(fallback);
        try {
          final response = allowStreaming
              ? await _chatWithStreaming(systemPrompt, messages, text, maxTokens)
              : await _chatWithModel(systemPrompt, messages, text, maxTokens);
          if (modelId != originalModel) switchModel(originalModel);
          return response;
        } catch (e2) {
          _log.e('Fallback $fallback also failed: $e2');
          recordFailure(fallback);
        }
      }
      if (modelId != originalModel) switchModel(originalModel);
      rethrow;
    }
  }

  Stream<String> chatStream({
    required String systemPrompt,
    required List<Map<String, String>> messages,
    String? userText,
    int maxTokens = 512,
  }) async* {
    final text = userText ?? messages.lastOrNull?['content'] ?? '';
    final conversationTokens = _tokenEstimator.estimateMessages(messages);
    final modelId = suggestBestModel(text, conversationTokens);
    final originalModel = _currentModelId;

    if (modelId != _currentModelId) {
      _log.i('Stream cost-aware routing: $modelId');
      switchModel(modelId);
    }

    try {
      if (isGoogleModel) {
        yield* _streamFromGemini(systemPrompt, messages, text, maxTokens);
      } else {
        yield* _streamFromOpenRouter(systemPrompt, messages, text, maxTokens);
      }
      recordFailure(currentModelId);
    } catch (e) {
      _log.e('Stream model $currentModelId failed: $e');
      recordFailure(currentModelId);
      final fallback = findFallbackModel();
      if (fallback != null && fallback != currentModelId) {
        _log.i('Stream failing over to $fallback');
        switchModel(fallback);
        try {
          if (isGoogleModel) {
            yield* _streamFromGemini(systemPrompt, messages, text, maxTokens);
          } else {
            yield* _streamFromOpenRouter(systemPrompt, messages, text, maxTokens);
          }
          recordFailure(fallback);
        } catch (e2) {
          _log.e('Stream fallback $fallback failed: $e2');
          recordFailure(fallback);
        }
      }
    } finally {
      if (modelId != originalModel) switchModel(originalModel);
    }
  }

  Future<LLMResponse> _chatWithModel(
    String systemPrompt,
    List<Map<String, String>> messages,
    String text,
    int maxTokens,
  ) async {
    final stopwatch = Stopwatch()..start();
    String result;

    if (isGoogleModel) {
      result = await _chatWithGemini(systemPrompt, messages, text, maxTokens);
    } else {
      result = await _chatWithOpenRouter(systemPrompt, messages, text, maxTokens);
    }

    stopwatch.stop();
    return LLMResponse(
      text: result,
      modelUsed: _currentModelId,
      tokensUsed: _tokenEstimator.estimate(result),
      latency: stopwatch.elapsed,
    );
  }

  Future<LLMResponse> _chatWithStreaming(
    String systemPrompt,
    List<Map<String, String>> messages,
    String text,
    int maxTokens,
  ) async {
    final buffer = StringBuffer();
    final stopwatch = Stopwatch()..start();

    await for (final chunk in chatStream(
      systemPrompt: systemPrompt,
      messages: messages,
      userText: text,
      maxTokens: maxTokens,
    )) {
      buffer.write(chunk);
    }

    stopwatch.stop();
    final full = buffer.toString();
    return LLMResponse(
      text: full,
      modelUsed: _currentModelId,
      tokensUsed: _tokenEstimator.estimate(full),
      fromStream: true,
      latency: stopwatch.elapsed,
    );
  }

  Stream<String> _streamFromOpenRouter(
    String systemPrompt,
    List<Map<String, String>> messages,
    String text,
    int maxTokens,
  ) async* {
    final apiKey = await getApiKey('OPENROUTER_API_KEY');
    if (apiKey.isEmpty) {
      yield "No OpenRouter API key configured.";
      return;
    }

    final requestMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages,
      {'role': 'user', 'content': text},
    ];

    final request = http.Request('POST', Uri.parse('$_openRouterBase/chat/completions'));
    request.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://ultron.app',
      'X-Title': 'Ultron Mobile',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'model': _currentModelId,
      'messages': requestMessages,
      'max_tokens': maxTokens,
      'temperature': 0.7,
      'stream': true,
    });

    final response = await http.Client().send(request).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('OpenRouter returned ${response.statusCode}: $body');
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield content;
            }
          }
        } catch (_) {}
      }
    }
  }

  Stream<String> _streamFromGemini(
    String systemPrompt,
    List<Map<String, String>> messages,
    String text,
    int maxTokens,
  ) async* {
    final apiKey = await getApiKey('GOOGLE_API_KEY');
    if (apiKey.isEmpty) {
      yield "No Google AI API key configured.";
      return;
    }

    final history = _buildGeminiHistory(messages);

    final model = GenerativeModel(
      model: geminiModelName,
      apiKey: apiKey,
      systemInstruction: Content.text(systemPrompt),
      generationConfig: GenerationConfig(
        maxOutputTokens: maxTokens,
        temperature: 0.7,
      ),
    );

    final chat = model.startChat(history: history);
    final response = chat.sendMessageStream(Content.text(text));

    await for (final chunk in response) {
      final chunkText = chunk.text;
      if (chunkText != null && chunkText.isNotEmpty) {
        yield chunkText;
      }
    }
  }

  Future<String> _chatWithGemini(
    String systemPrompt,
    List<Map<String, String>> messages,
    String text,
    int maxTokens,
  ) async {
    final apiKey = await getApiKey('GOOGLE_API_KEY');
    if (apiKey.isEmpty) {
      return "No Google AI API key configured.";
    }

    final history = _buildGeminiHistory(messages);

    final model = GenerativeModel(
      model: geminiModelName,
      apiKey: apiKey,
      systemInstruction: Content.text(systemPrompt),
      generationConfig: GenerationConfig(
        maxOutputTokens: maxTokens,
        temperature: 0.7,
      ),
    );

    final chat = model.startChat(history: history);
    final response = await chat.sendMessage(Content.text(text));
    return response.text ?? "I processed that but have no response.";
  }

  Future<String> _chatWithOpenRouter(
    String systemPrompt,
    List<Map<String, String>> messages,
    String text,
    int maxTokens,
  ) async {
    final apiKey = await getApiKey('OPENROUTER_API_KEY');
    if (apiKey.isEmpty) {
      return "No OpenRouter API key configured.";
    }

    final requestMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages,
      {'role': 'user', 'content': text},
    ];

    final res = await http.post(
      Uri.parse('$_openRouterBase/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://ultron.app',
        'X-Title': 'Ultron Mobile',
      },
      body: jsonEncode({
        'model': _currentModelId,
        'messages': requestMessages,
        'max_tokens': maxTokens,
        'temperature': 0.7,
      }),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('OpenRouter returned ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final choice = (data['choices'] as List).first;
    return (choice['message']['content'] as String?) ?? "I processed that but have no response.";
  }

  List<Content> _buildGeminiHistory(List<Map<String, String>> messages) {
    final raw = <Content>[];
    for (final msg in messages) {
      final role = msg['role'];
      final content = msg['content'] ?? '';
      if (role == 'user') {
        raw.add(Content.text(content));
      } else if (role == 'assistant') {
        raw.add(Content.model([TextPart(content)]));
      }
    }
    final history = <Content>[];
    String? lastRole;
    for (final c in raw) {
      final role = c.role;
      if (role == lastRole) {
        if (history.isNotEmpty) history.removeLast();
        lastRole = history.isNotEmpty ? history.last.role : null;
      }
      history.add(c);
      lastRole = role;
    }
    if (history.isNotEmpty && history.first.role == 'model') {
      history.removeAt(0);
    }
    if (history.length > 1 && history.last.role != 'user') {
      history.removeLast();
    }
    return history;
  }
}
