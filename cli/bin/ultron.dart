import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  print('');
  print('  \x1b[1;31m  _   _ _     _ _____ ___  _   _  \x1b[0m');
  print('  \x1b[1;31m | | | | |   | |_   _/ _ \\| \\ | | \x1b[0m');
  print('  \x1b[1;31m | | | | |   | | | || | | |  \\| | \x1b[0m');
  print('  \x1b[1;31m | |_| | |___| | | || |_| | |\\  | \x1b[0m');
  print('  \x1b[1;31m  \\___/|_____|_| |_| \\___/|_| \\_| \x1b[0m');
  print('');
  print('  \x1b[1;36m  CLI Mode  --  Type /help for commands\x1b[0m');
  print('');

  final cli = UltronCLI();
  await cli.loadConfig();
  await cli.run();
}

class UltronCLI {
  String _apiKey = '';
  String _model = 'openai/gpt-4o-mini';
  bool _running = true;
  final List<Map<String, String>> _history = [];
  final List<String> _memories = [];

  String get _home => Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '.';
  String get _configFile => '$_home/.ultron/config.json';
  String get _memoryFile => '$_home/.ultron/memory.json';

  Future<void> loadConfig() async {
    _apiKey = Platform.environment['OPENROUTER_API_KEY'] ?? '';
    final f = File(_configFile);
    if (await f.exists()) {
      try {
        final d = jsonDecode(await f.readAsString()) as Map;
        _apiKey = d['key'] as String? ?? _apiKey;
        _model = d['model'] as String? ?? _model;
      } catch (_) {}
    }
    final mf = File(_memoryFile);
    if (await mf.exists()) {
      try { _memories.addAll((jsonDecode(await mf.readAsString()) as List).cast()); }
      catch (_) {}
    }
    if (_apiKey.isEmpty) {
      print('  \x1b[33mSet your API key: /api openrouter_key=sk-or-...\x1b[0m');
      print('');
    }
  }

  Future<void> _save() async {
    final dir = Directory('$_home/.ultron');
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(_configFile).writeAsString(jsonEncode({'key': _apiKey, 'model': _model}));
    await File(_memoryFile).writeAsString(jsonEncode(_memories));
  }

  Future<void> run() async {
    while (_running) {
      stdout.write('\r\x1b[1;31mULTRON\x1b[0m > ');
      final line = stdin.readLineSync(encoding: utf8);
      if (line == null) break;
      final input = line.trim();
      if (input.isEmpty) continue;
      if (input.startsWith('/')) { await _cmd(input.substring(1)); }
      else { await _chat(input); }
    }
  }

  Future<void> _cmd(String c) async {
    final p = c.trim().split(RegExp(r'\s+'));
    final cmd = p.first.toLowerCase();
    final a = p.skip(1).join(' ');
    switch (cmd) {
      case 'help':
        print('  \x1b[33m/help\x1b[0m              Help');
        print('  \x1b[33m/quit\x1b[0m              Exit');
        print('  \x1b[33m/model <id>\x1b[0m        Switch model');
        print('  \x1b[33m/api key=val\x1b[0m       Set key (openrouter_key=sk-or-...)');
        print('  \x1b[33m/clear\x1b[0m             Clear session');
      case 'quit': case 'exit': await _save(); _running = false;
      case 'model': if (a.isEmpty) { print('Model: $_model'); } else { _model = a; await _save(); print('Model: $_model'); }
      case 'api':
        final i = a.indexOf('='); if (i < 0) { print('Usage: /api key=value'); return; }
        final k = a.substring(0, i).trim(), v = a.substring(i + 1).trim();
        if (k.contains('openrouter')) _apiKey = v;
        else { print('Unknown key'); return; }
        await _save(); print('Key saved.');
      case 'clear': _history.clear(); print('Session cleared.');
      default: print('Unknown. Type /help');
    }
  }

  Future<void> _chat(String text) async {
    if (_apiKey.isEmpty) { print('\x1b[31mULTRON\x1b[0m: No API key. Use /api openrouter_key=sk-or-...'); return; }
    _history.add({'role': 'user', 'content': text});
    print('');

    try {
      final body = jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': 'You are ULTRON, a concise CLI AI assistant. Answer in 1-3 sentences.'},
          ..._history,
        ],
        'max_tokens': 1024,
        'temperature': 0.7,
      });

      final res = await _post(
        'https://openrouter.ai/api/v1/chat/completions',
        body: body,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map;
        final content = ((data['choices'] as List).first['message']['content'] as String?)?.trim() ?? '';
        print('\x1b[1;31mULTRON\x1b[0m: $content');
        _history.add({'role': 'assistant', 'content': content});
        if (text.length > 5 && !text.toLowerCase().contains('forget')) {
          _memories.add('[${DateTime.now().toIso8601String()}] $text');
          if (_memories.length > 200) _memories.removeAt(0);
          await _save();
        }
      } else {
        _history.removeLast();
        if (res.statusCode == 401) {
          print('\x1b[31mULTRON\x1b[0m: Invalid API key. Use /api openrouter_key=sk-or-...');
        } else if (res.statusCode == 429) {
          print('\x1b[31mULTRON\x1b[0m: Rate limited. Retrying...');
          await Future.delayed(const Duration(seconds: 3));
          return _chat(text);
        } else {
          print('\x1b[31mError\x1b[0m: HTTP ${res.statusCode}');
        }
      }
    } catch (e) {
      _history.removeLast();
      print('\x1b[31mError\x1b[0m: $e');
    }
  }

  Future<_Response> _post(String url, {required String body, required Map<String, String> headers}) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.postUrl(uri);
      headers.forEach((k, v) => req.headers.set(k, v));
      req.write(body);
      final res = await req.close();
      final responseBody = await res.transform(utf8.decoder).join();
      return _Response(res.statusCode, responseBody);
    } finally {
      client.close();
    }
  }
}

class _Response {
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
}
