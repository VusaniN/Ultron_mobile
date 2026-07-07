class TokenEstimator {
  TokenEstimator._();

  static final TokenEstimator _instance = TokenEstimator._();
  factory TokenEstimator() => _instance;

  static const double _englishRatio = 0.85;

  int estimate(String text) {
    if (text.isEmpty) return 0;
    int tokens = 0;
    int i = 0;
    while (i < text.length) {
      final code = text.codeUnitAt(i);
      if (code < 128) {
        tokens++;
        i += _tokensForChar(text, i);
      } else if (code < 2048) {
        tokens += 2;
        i++;
      } else {
        tokens += 3;
        i++;
      }
    }
    int spaces = ' '.allMatches(text).length;
    tokens = (tokens * _englishRatio + spaces * 0.5).round();
    return (tokens * 0.75).round().clamp(1, text.length);
  }

  int _tokensForChar(String text, int start) {
    const String special = r'''.,!?;:()[]{}"'-@#$%^&*+=/\|~`<>''';
    if (start + 1 < text.length) {
      final current = text[start];
      final next = text[start + 1];
      if (current == ' ' && next == ' ') return 2;
      if (special.contains(current) && current != next) return 1;
    }
    return 1;
  }

  int estimateMessages(List<Map<String, String>> messages) {
    int total = 0;
    for (final msg in messages) {
      total += estimate(msg['role'] ?? '');
      total += estimate(msg['content'] ?? '');
    }
    return total;
  }

  List<Map<String, String>> truncateToLimit(
    List<Map<String, String>> messages,
    int maxTokens, {
    int reserveForResponse = 256,
    int systemPromptTokens = 200,
  }) {
    final available = maxTokens - systemPromptTokens - reserveForResponse;
    if (available <= 0) return [];
    final truncated = <Map<String, String>>[];
    int running = 0;
    for (int i = messages.length - 1; i >= 0; i--) {
      final tokens = estimateMessages([messages[i]]);
      if (running + tokens > available) break;
      running += tokens;
      truncated.insert(0, messages[i]);
    }
    return truncated;
  }
}
