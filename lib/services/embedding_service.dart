import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/logger.dart';

class EmbeddingService {
  OpenRouterEmbedding? _openRouter;

  EmbeddingService({required String? apiKey, String model = 'text-embedding-3-small'}) {
    if (apiKey != null && apiKey.startsWith('AIza')) {
      _openRouter = OpenRouterEmbedding(apiKey: apiKey, model: model);
    }
  }

  void init({required String openRouterKey}) {
    if (openRouterKey.isNotEmpty) {
      _openRouter = OpenRouterEmbedding(apiKey: openRouterKey, model: 'openai/text-embedding-3-small');
    }
  }

  Future<List<double>> embed(String text) async {
    if (_openRouter != null) {
      final result = await _openRouter!.embed(text);
      if (result != null) return result;
    }
    return _fallbackHashEmbed(text);
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (_openRouter != null) {
      final result = await _openRouter!.embedBatch(texts);
      if (result != null) return result;
    }
    return texts.map(_fallbackHashEmbed).toList();
  }

  List<double> _fallbackHashEmbed(String text) {
    final hash = text.hashCode;
    final seed = hash & 0xFFFFFFFF;
    final rng = _SimpleRNG(seed);
    return List.generate(64, (_) => (rng.next() * 2.0) - 1.0);
  }

  double similarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final mag = (na * nb).clamp(1e-10, double.infinity);
    return dot / mag;
  }
}

class _SimpleRNG {
  int _state;
  _SimpleRNG(int seed) : _state = seed;
  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state / 0x7FFFFFFF;
  }
}

class OpenRouterEmbedding {
  final String apiKey;
  final String model;
  final Logger _log = Logger('OpenRouterEmbedding');
  static const _baseUrl = 'https://openrouter.ai/api/v1/embeddings';

  OpenRouterEmbedding({required this.apiKey, this.model = 'openai/text-embedding-3-small'});

  Future<List<double>?> embed(String text) async {
    try {
      final res = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'input': text,
        }),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final vec = data['data']?[0]?['embedding'] as List?;
        if (vec != null) return vec.cast<double>();
      } else {
        _log.w('Embedding API error ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      _log.d('Embedding API call failed, using fallback: $e');
    }
    return null;
  }

  Future<List<List<double>>?> embedBatch(List<String> texts) async {
    try {
      final res = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'input': texts,
        }),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final embeddings = data['data'] as List?;
        if (embeddings != null) {
          return embeddings.map((e) => (e['embedding'] as List).cast<double>()).toList();
        }
      }
    } catch (e) {
      _log.d('Batch embedding failed: $e');
    }
    return null;
  }
}
