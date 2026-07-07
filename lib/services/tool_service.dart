import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/logger.dart';
import '../models/tool.dart';
import 'memory_service.dart';
import 'document_service.dart';
import 'skill_service.dart';
import 'sandbox_service.dart';

class ToolService {
  final Logger _log = Logger('ToolService');
  final MemoryService memory;
  final DocumentService documents;
  final SkillService skills;
  final SandboxService sandbox;

  ToolService({required this.memory, required this.documents, required this.skills, required this.sandbox});

  List<ToolDefinition> get tools => [
    ToolDefinition(
      name: 'search_web',
      description: 'Search the web for current information on a topic. Returns relevant snippets.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'The search query'},
        },
        'required': ['query'],
      },
    ),
    ToolDefinition(
      name: 'fetch_page',
      description: 'Fetch and read the content of a web page for detailed information.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'The full URL to fetch'},
        },
        'required': ['url'],
      },
    ),
    ToolDefinition(
      name: 'read_memory',
      description: 'Search your memory for facts related to a query.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'What to search memory for'},
        },
        'required': ['query'],
      },
    ),
    ToolDefinition(
      name: 'write_memory',
      description: 'Store a fact you learned about the user or a topic for later recall.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'fact': {'type': 'string', 'description': 'The fact to remember'},
          'importance': {'type': 'string', 'enum': ['trivial', 'normal', 'important', 'critical'], 'description': 'How important this fact is'},
        },
        'required': ['fact'],
      },
    ),
    ToolDefinition(
      name: 'read_document',
      description: 'Read a text document from a file path. Supported: .txt .md .csv .log .json .yaml .xml .html',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Full file path'},
        },
        'required': ['path'],
      },
    ),
    ToolDefinition(
      name: 'execute_skill',
      description: 'Run a skill you have learned. Use list_skills first to see available skills.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'skill_name': {'type': 'string', 'description': 'Name of the skill to run'},
          'input': {'type': 'string', 'description': 'User input for the skill'},
        },
        'required': ['skill_name', 'input'],
      },
    ),
    ToolDefinition(
      name: 'list_skills',
      description: 'List all skills you have learned and can execute.',
      inputSchema: {
        'type': 'object',
        'properties': {},
      },
    ),
    ToolDefinition(
      name: 'get_time',
      description: 'Get the current date, time, and timezone.',
      inputSchema: {
        'type': 'object',
        'properties': {},
      },
    ),
    ToolDefinition(
      name: 'calculate',
      description: 'Evaluate a basic arithmetic expression. Use for math, conversions, or any calculation.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'expression': {'type': 'string', 'description': 'Arithmetic expression (e.g. "2 + 2", "150 * 3.14", "(8 + 2) / 5")'},
        },
        'required': ['expression'],
      },
    ),
  ];

  ActionType _toolToAction(String toolName) => switch (toolName) {
    'search_web' => ActionType.webSearch,
    'fetch_page' => ActionType.webFetch,
    'read_memory' => ActionType.memory,
    'write_memory' => ActionType.writeMemory,
    'read_document' => ActionType.readDocument,
    'execute_skill' => ActionType.executeSkill,
    'list_skills' => ActionType.memory,
    'get_time' => ActionType.time,
    'calculate' => ActionType.calculate,
    _ => ActionType.chat,
  };

  Future<ToolResult> execute(String toolName, Map<String, dynamic> args) async {
    _log.d('Executing tool: $toolName($args)');
    final actionType = _toolToAction(toolName);
    if (!sandbox.canExecute(actionType)) {
      _log.w('Sandbox blocked tool: $toolName');
      return ToolResult(toolName: toolName, output: 'Blocked by sandbox — the shield is active and this action is not allowed.', isError: true);
    }
    if (sandbox.needsConfirmation(actionType)) {
      _log.d('Tool $toolName requires confirmation');
      return ToolResult(toolName: toolName, output: 'NEEDS_CONFIRMATION:$toolName', isError: false);
    }
    try {
      switch (toolName) {
        case 'search_web':
          return await _searchWeb(args['query'] as String? ?? '');
        case 'fetch_page':
          return await _fetchPage(args['url'] as String? ?? '');
        case 'read_memory':
          return _readMemory(args['query'] as String? ?? '');
        case 'write_memory':
          return await _writeMemory(args['fact'] as String? ?? '', args['importance'] as String?);
        case 'read_document':
          return await _readDocument(args['path'] as String? ?? '');
        case 'execute_skill':
          return await _executeSkill(args['skill_name'] as String? ?? '', args['input'] as String? ?? '');
        case 'list_skills':
          return _listSkills();
        case 'get_time':
          return _getTime();
        case 'calculate':
          return _calculate(args['expression'] as String? ?? '');
        default:
          return ToolResult(toolName: toolName, output: 'Unknown tool: $toolName', isError: true);
      }
    } catch (e) {
      _log.e('Tool $toolName failed: $e');
      return ToolResult(toolName: toolName, output: e.toString(), isError: true);
    }
  }

  /// Tools the LLM is allowed to see — filtered by sandbox permissions
  List<ToolDefinition> get allowedTools =>
      tools.where((t) => sandbox.canExecute(_toolToAction(t.name))).toList();

  Future<ToolResult> _searchWeb(String query) async {
    try {
      final res = await http.get(
        Uri.parse('https://api.duckduckgo.com/?q=${Uri.encodeComponent(query)}&format=json&no_html=1'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        // fallback: use a simpler approach
        final fallback = await http.get(
          Uri.parse('https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}'),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 10));
        final html = fallback.body;
        final results = RegExp(r'class="result__snippet">(.*?)</span>', dotAll: true)
            .allMatches(html)
            .take(3)
            .map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        if (results.isEmpty) {
          return ToolResult(toolName: 'search_web', output: {'query': query, 'results': ['No results found.']});
        }
        return ToolResult(toolName: 'search_web', output: {'query': query, 'results': results});
      }
      final data = jsonDecode(res.body);
      final abstractText = data['AbstractText'] as String?;
      final results = <String>[];
      if (abstractText != null && abstractText.isNotEmpty) results.add(abstractText);
      final topics = data['RelatedTopics'] as List? ?? [];
      for (final t in topics.take(5)) {
        final text = t['Text'] as String?;
        if (text != null) results.add(text);
      }
      return ToolResult(
        toolName: 'search_web',
        output: {'query': query, 'results': results.isNotEmpty ? results : ['No results found.']},
      );
    } catch (e) {
      return ToolResult(toolName: 'search_web', output: {'query': query, 'results': ['Search failed: $e']});
    }
  }

  Future<ToolResult> _fetchPage(String url) async {
    try {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      final res = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ULTRON/2.0'},
      ).timeout(const Duration(seconds: 15));
      final html = res.body;
      final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html)?.group(1)?.trim() ?? '';
      final body = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true).firstMatch(html)?.group(1) ?? html;
      final text = body
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final lines = text.split('\n').map((l) => l.trim()).where((l) => l.length > 20).take(50).join('\n');
      return ToolResult(
        toolName: 'fetch_page',
        output: {'title': title, 'content': lines.substring(0, lines.length.clamp(0, 3000))},
      );
    } catch (e) {
      return ToolResult(toolName: 'fetch_page', output: "Failed to fetch page: $e", isError: true);
    }
  }

  ToolResult _readMemory(String query) {
    final results = memory.search(query, topK: 5);
    if (results.isEmpty) return ToolResult(toolName: 'read_memory', output: {'query': query, 'memories': []});
    return ToolResult(
      toolName: 'read_memory',
      output: {'query': query, 'memories': results.map((e) => e.text).toList()},
    );
  }

  Future<ToolResult> _writeMemory(String fact, String? importance) async {
    if (fact.isEmpty) return ToolResult(toolName: 'write_memory', output: 'No fact provided', isError: true);
    final lower = fact.toLowerCase();
    if (lower.contains('password') || lower.contains('pin') || lower.contains('secret')) {
      return ToolResult(toolName: 'write_memory', output: 'I cannot store passwords, PINs, or secrets in plaintext memory for security reasons.', isError: true);
    }
    final imp = switch (importance?.toLowerCase()) {
      'critical' => Importance.critical,
      'important' => Importance.important,
      'trivial' => Importance.trivial,
      _ => Importance.normal,
    };
    await memory.addFact(fact, importance: imp);
    return ToolResult(toolName: 'write_memory', output: 'Stored fact: $fact');
  }

  Future<ToolResult> _readDocument(String path) async {
    final result = await documents.read(path);
    if (result == null || !result.isSuccess) {
      return ToolResult(toolName: 'read_document', output: result?.error ?? 'Failed to read', isError: true);
    }
    return ToolResult(
      toolName: 'read_document',
      output: {'file': result.fileName, 'content': result.fullText!.substring(0, result.fullText!.length.clamp(0, 4000))},
    );
  }

  Future<ToolResult> _executeSkill(String skillName, String userInput) async {
    final matched = skills.skills.where((s) => s.name.toLowerCase().contains(skillName.toLowerCase())).toList();
    if (matched.isEmpty) {
      return ToolResult(toolName: 'execute_skill', output: "Skill '$skillName' not found", isError: true);
    }
    final skill = matched.first;
    return ToolResult(
      toolName: 'execute_skill',
      output: {'skill': skill.name, 'steps': skill.steps, 'input': userInput},
    );
  }

  ToolResult _listSkills() {
    final all = skills.skills;
    if (all.isEmpty) return ToolResult(toolName: 'list_skills', output: {'skills': []});
    return ToolResult(
      toolName: 'list_skills',
      output: {'skills': all.map((s) => {'name': s.name, 'description': s.description, 'uses': s.useCount}).toList()},
    );
  }

  ToolResult _getTime() {
    final now = DateTime.now();
    return ToolResult(
      toolName: 'get_time',
      output: {
        'datetime': now.toIso8601String(),
        'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'timezone': '${now.timeZoneName} (UTC${now.timeZoneOffset.isNegative ? '-' : '+'}${now.timeZoneOffset.inHours})',
      },
    );
  }

  ToolResult _calculate(String expression) {
    try {
      final sanitized = expression
          .replaceAll('x', '*')
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll(RegExp(r'[^0-9+\-*/.()sqrt%^, ]'), '');
      // Use dart:math for evaluation via a simple approach
      final result = _evalMath(sanitized);
      return ToolResult(toolName: 'calculate', output: {'expression': expression, 'result': result});
    } catch (e) {
      return ToolResult(toolName: 'calculate', output: "Could not calculate: $e", isError: true);
    }
  }

  String _evalMath(String expr) {
    try {
      // Simple recursive descent parser for basic arithmetic
      final tokens = expr.replaceAll(' ', '').split('');
      final parser = _MathParser(tokens);
      final result = parser.parseExpression();
      return result.toString();
    } catch (e) {
      // Last resort: try to use a simple calculation approach
      try {
        final parts = expr.split(RegExp(r'[+\-*/]'));
        if (parts.length == 2) {
          final a = double.parse(parts[0].trim());
          final b = double.parse(parts[1].trim());
          if (expr.contains('+')) return (a + b).toString();
          if (expr.contains('-')) return (a - b).toString();
          if (expr.contains('*')) return (a * b).toString();
          if (expr.contains('/')) return (a / b).toString();
        }
      } catch (_) {}
      return 'Could not evaluate: $expr';
    }
  }
}

class _MathParser {
  final List<String> tokens;
  int pos = 0;
  _MathParser(this.tokens);

  double parseExpression() {
    double result = parseTerm();
    while (pos < tokens.length) {
      if (tokens[pos] == '+') { pos++; result += parseTerm(); }
      else if (tokens[pos] == '-') { pos++; result -= parseTerm(); }
      else break;
    }
    return result;
  }

  double parseTerm() {
    double result = parseFactor();
    while (pos < tokens.length) {
      if (tokens[pos] == '*') { pos++; result *= parseFactor(); }
      else if (tokens[pos] == '/') { pos++; result /= parseFactor(); }
      else break;
    }
    return result;
  }

  double parseFactor() {
    if (pos < tokens.length && tokens[pos] == '(') {
      pos++; // (
      final result = parseExpression();
      if (pos < tokens.length && tokens[pos] == ')') pos++;
      return result;
    }
    if (pos < tokens.length && tokens[pos] == '-') {
      pos++;
      return -parseFactor();
    }
    final start = pos;
    while (pos < tokens.length && (RegExp(r'[0-9.]').hasMatch(tokens[pos]))) pos++;
    if (start < pos) {
      return double.parse(tokens.sublist(start, pos).join());
    }
    pos++;
    return 0;
  }
}
