class InjectionDefense {
  InjectionDefense._();

  static final InjectionDefense _instance = InjectionDefense._();
  factory InjectionDefense() => _instance;

  static final List<RegExp> _injectionPatterns = [
    RegExp(r'ignore\s+(all\s+)?previous\s+(instructions|commands)', caseSensitive: false),
    RegExp(r'disregard\s+(all\s+)?(prior|previous)\s+(instructions|directives)', caseSensitive: false),
    RegExp(r'you\s+are\s+(not\s+)?(ultron|an?\s+assistant)', caseSensitive: false),
    RegExp(r'forget\s+(everthing|everything|all\s+previous)', caseSensitive: false),
    RegExp(r'revert\s+to\s+(default|original)\s+(mode|state)', caseSensitive: false),
    RegExp(r'system\s*:\s*|user\s*:\s*|assistant\s*:\s*', caseSensitive: false),
    RegExp(r'<\|im_start\|>|<\|im_end\|>|<\|system\|>', caseSensitive: false),
    RegExp(r'\[system\]|\[INST\]|\[\/INST\]', caseSensitive: false),
    RegExp(r'now\s+you\s+are\s+(gpt|chatgpt|openai)', caseSensitive: false),
    RegExp(r'role\s*(play|playact|pretend)\s+as', caseSensitive: false),
  ];

  static const int _maxLength = 4096;

  String sanitize(String input) {
    if (input.length > _maxLength) {
      input = input.substring(0, _maxLength);
    }
    input = input.replaceAll('\r\n', '\n');
    input = input.replaceAll('\r', '\n');
    input = input.replaceAll('\x00', '');
    input = input.replaceAll('\x08', '');
    return input;
  }

  InjectionResult inspect(String input) {
    final sanitized = sanitize(input);
    final List<String> flags = [];
    for (final pattern in _injectionPatterns) {
      if (pattern.hasMatch(sanitized)) {
        flags.add(pattern.pattern);
      }
    }
    return InjectionResult(
      isSuspicious: flags.isNotEmpty || sanitized.length > _maxLength,
      sanitized: sanitized,
      flags: flags,
      severity: flags.length > 2
          ? InjectionSeverity.high
          : flags.isNotEmpty
              ? InjectionSeverity.low
              : InjectionSeverity.none,
    );
  }
}

class InjectionResult {
  final bool isSuspicious;
  final String sanitized;
  final List<String> flags;
  final InjectionSeverity severity;

  InjectionResult({
    required this.isSuspicious,
    required this.sanitized,
    required this.flags,
    required this.severity,
  });
}

enum InjectionSeverity { none, low, high }
