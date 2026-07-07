import '../core/logger.dart';

enum IntentType {
  deviceCommand,
  conversational,
  memory,
  system,
}

class IntentResult {
  final IntentType type;
  final String action;
  final String params;
  final double confidence;

  const IntentResult({
    required this.type,
    required this.action,
    required this.params,
    required this.confidence,
  });

  bool get isDeviceCommand => type == IntentType.deviceCommand;
  bool get isMemory => type == IntentType.memory;
  bool get isConversational => type == IntentType.conversational;
  bool get isHighConfidence => confidence >= 0.7;
}

class IntentService {
  final Logger _log = Logger('IntentService');

  static final List<_CommandPattern> _commandPatterns = [
    _CommandPattern(r'\b(joke|funny|laugh|make me laugh)\b', 'joke', 0.85),
    _CommandPattern(r'\b(time|what time|current time)\b', 'time', 0.9),
    _CommandPattern(r'\b(battery|charge level|power left|how much battery)\b', 'battery', 0.9),
    _CommandPattern(r'\b(volume)\s*(up|down|max|min|\d+)\b', 'volume', 0.85),
    _CommandPattern(r'^(open|launch|start|run)\s+', 'launch', 0.95),
    _CommandPattern(r'^(search|look up|google|find|search for)\s+', 'search', 0.95),
    _CommandPattern(r'^(remember|save|note)\s+(that|this)?\s', 'memory_save', 0.9),
    _CommandPattern(r'^(forget|delete memory|remove memory)\s+', 'memory_forget', 0.9),
    _CommandPattern(r'^(what do you remember|recall|show memory|my memories)\b', 'memory_recall', 0.9),
    _CommandPattern(r'^save session|^save this conversation', 'memory_save_session', 0.85),
    _CommandPattern(r'^(set volume|volume set)\s+to\s+(\d+)', 'volume', 0.9),
    _CommandPattern(r'^(turn up|turn down|increase|decrease)\s+(volume|sound)', 'volume_adjust', 0.8),
    _CommandPattern(r'^(mute|unmute|silent|silence)\b', 'volume_mute', 0.8),
  ];

  static final List<String> _conversationalTriggers = [
    'what is', 'what are', 'how do', 'why is', 'why are',
    'can you explain', 'tell me about', 'what do you think',
    'how does', 'where is', 'who is', 'when was',
    'define', 'meaning of', 'difference between',
  ];

  IntentResult classify(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) {
      return IntentResult(
        type: IntentType.conversational,
        action: 'chat',
        params: '',
        confidence: 0.0,
      );
    }

    if (lower.startsWith('remember') || lower.startsWith('forget') ||
        lower.startsWith('recall') || lower.startsWith('save session') ||
        lower.startsWith('what do you remember') || lower.startsWith('show memory') ||
        lower.startsWith('my memories')) {
      return IntentResult(
        type: IntentType.memory,
        action: 'memory',
        params: lower,
        confidence: 0.9,
      );
    }

    for (final pattern in _commandPatterns) {
      final match = pattern.regex.firstMatch(lower);
      if (match != null) {
        final isLikelyCommand = _isLikelyCommand(lower, pattern.action);
        if (isLikelyCommand) {
          final params = match.groupCount >= 1
              ? (match.group(1) ?? '')
              : lower.replaceFirst(pattern.regex, '').trim();
          _log.d('Classified as command: ${pattern.action} (conf: ${pattern.confidence})');
          return IntentResult(
            type: IntentType.deviceCommand,
            action: pattern.action,
            params: params,
            confidence: pattern.confidence,
          );
        }
      }
    }

    for (final trigger in _conversationalTriggers) {
      if (lower.startsWith(trigger)) {
        return IntentResult(
          type: IntentType.conversational,
          action: 'chat',
          params: lower,
          confidence: 0.85,
        );
      }
    }

    if (lower.length < 10) {
      return IntentResult(
        type: IntentType.conversational,
        action: 'chat',
        params: lower,
        confidence: 0.5,
      );
    }

    return IntentResult(
      type: IntentType.conversational,
      action: 'chat',
      params: lower,
      confidence: 0.65,
    );
  }

  bool _isLikelyCommand(String lower, String action) {
    switch (action) {
      case 'joke':
        return lower.startsWith('tell') || lower.startsWith('say') ||
               lower.startsWith('give') || lower.startsWith('make') ||
               lower.endsWith('joke') || lower.endsWith('joke!');
      case 'time':
        return lower.split(' ').length <= 6;
      case 'battery':
        return lower.split(' ').length <= 6;
      case 'volume':
        return true;
      case 'launch':
        return true;
      case 'search':
        return true;
      default:
        return true;
    }
  }
}

class _CommandPattern {
  final RegExp regex;
  final String action;
  final double confidence;

  _CommandPattern(String pattern, this.action, this.confidence)
    : regex = RegExp(pattern, caseSensitive: false);
}
