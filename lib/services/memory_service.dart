import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import '../core/logger.dart';
import 'embedding_service.dart';

enum MemoryType { fact, session, preference }

enum Importance { trivial, normal, important, critical }

class MemoryEntry {
  final String id;
  final String text;
  final MemoryType type;
  final DateTime createdAt;
  final DateTime? expiresAt;
  List<double>? _embedding;
  final Importance importance;
  int accessCount;
  Completer<void>? _embeddingCompleter;

  MemoryEntry({
    required this.id,
    required this.text,
    required this.type,
    required this.createdAt,
    this.expiresAt,
    List<double>? embedding,
    this.importance = Importance.normal,
    this.accessCount = 0,
  }) : _embedding = embedding;

  List<double>? get embedding => _embedding;
  set embedding(List<double>? v) {
    _embedding = v;
    if (_embeddingCompleter != null && v != null) {
      _embeddingCompleter!.complete();
      _embeddingCompleter = null;
    }
  }

  Future<void> ensureEmbedding(EmbeddingService emb) async {
    if (_embedding != null) return;
    if (_embeddingCompleter != null) return _embeddingCompleter!.future;
    _embeddingCompleter = Completer<void>();
    final vec = await emb.embed(text);
    _embedding = vec;
    _embeddingCompleter!.complete();
  }

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  double get relevanceScore {
    final ageHours = DateTime.now().difference(createdAt).inHours;
    final ageFactor = 1.0 / (1.0 + ageHours / 24.0);
    final accessFactor = 1.0 + log(1 + accessCount) / log(10);
    final importanceFactor = switch (importance) {
      Importance.trivial => 0.3,
      Importance.normal => 1.0,
      Importance.important => 3.0,
      Importance.critical => 10.0,
    };
    return ageFactor * accessFactor * importanceFactor;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'type': type.name,
    'createdAt': createdAt.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (embedding != null) 'embedding': embedding,
    'importance': importance.name,
    'accessCount': accessCount,
  };

  factory MemoryEntry.fromJson(Map<String, dynamic> json) => MemoryEntry(
    id: json['id'] as String,
    text: json['text'] as String,
    type: MemoryType.values.byName(json['type'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt'] as String) : null,
    embedding: json['embedding'] != null
        ? (json['embedding'] as List).cast<double>()
        : null,
    importance: json['importance'] != null
        ? Importance.values.byName(json['importance'] as String)
        : Importance.normal,
    accessCount: json['accessCount'] as int? ?? 0,
  );
}

class MemoryService {
  static const int _maxEntries = 1000;
  static const int _autoSaveInterval = 5;

  final Logger _log = Logger('MemoryService');
  final EmbeddingService _embeddings;
  final String? _storageDir;
  List<MemoryEntry> _entries = [];
  File? _file;
  List<String> _currentSession = [];
  final Map<String, String> _preferences = {};
  int _messageCount = 0;

  MemoryService({required EmbeddingService embeddings, String? storageDir})
    : _embeddings = embeddings,
      _storageDir = storageDir;

  Future<void> init() async {
    try {
      final dir = _storageDir != null ? Directory(_storageDir!) : await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/ultron_memory.json');
      if (await _file!.exists()) {
        final data = await _file!.readAsString();
        if (data.isNotEmpty) {
          final list = jsonDecode(data) as List;
          _entries = list.map((e) => MemoryEntry.fromJson(e)).toList();
        }
      }
      _prune();
      _log.i('Memory initialized with ${_entries.length} entries');
    } catch (e) {
      _log.w('Memory init failed: $e');
    }
  }

  void _prune() {
    final before = _entries.length;
    _entries.removeWhere((e) => e.isExpired && e.importance != Importance.critical);
    if (_entries.length > _maxEntries) {
      _entries.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
      _entries = _entries.take(_maxEntries).toList();
    }
    if (_entries.length != before) {
      _log.i('Pruned ${before - _entries.length} expired entries');
      _save();
    }
  }

  Future<void> _save() async {
    if (_file == null) return;
    try {
      final data = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await _file!.writeAsString(data);
    } catch (e) {
      _log.e('Failed to save memory: $e');
    }
  }

  void recordMessage(String role, String text) {
    _currentSession.add('[$role]: $text');
  }

  Future<void> saveSession() async {
    if (_currentSession.length < 2) return;
    final now = DateTime.now();
    final text = _currentSession.join('\n');
    final entry = MemoryEntry(
      id: now.millisecondsSinceEpoch.toString(),
      text: text,
      type: MemoryType.session,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 1)),
      importance: Importance.trivial,
    );
    _entries.insert(0, entry);
    // compute embedding asynchronously
    entry.embedding = await _embeddings.embed(text);
    _prune();
    _currentSession.clear();
    await _save();
    _log.i('Session saved');
  }

  Future<Importance> addFact(String text, {Importance? importance, String? category}) async {
    final now = DateTime.now();
    Importance imp;
    try {
      imp = importance ?? _inferImportance(text);
    } on FormatException {
      _log.w('Rejected memory: $text');
      return Importance.trivial;
    }
    final retention = switch (imp) {
      Importance.trivial => const Duration(days: 1),
      Importance.normal => const Duration(days: 7),
      Importance.important => const Duration(days: 30),
      Importance.critical => null,
    };

    if (category != null) {
      _preferences[category] = text;
    }

    final entry = MemoryEntry(
      id: now.millisecondsSinceEpoch.toString(),
      text: text,
      type: MemoryType.fact,
      createdAt: now,
      expiresAt: retention != null ? now.add(retention) : null,
      importance: imp,
    );
    _entries.insert(0, entry);
    entry.embedding = await _embeddings.embed(text);
    _prune();
    await _save();
    _log.i('Fact saved ($imp): $text');
    return imp;
  }

  Importance _inferImportance(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('password') || lower.contains('pin') || lower.contains('secret')) {
      throw FormatException('Refusing to store secrets in plaintext memory. Use SecureStorage for sensitive data.');
    }
    if (lower.contains('emergency') || lower.contains('allergy') || lower.contains('medical') ||
        lower.contains('never forget') || lower.contains('important')) {
      return Importance.critical;
    }
    if (lower.contains('address') || lower.contains('phone') || lower.contains('email') ||
        lower.contains('birthday') || lower.contains('meeting') || lower.contains('appointment') ||
        lower.contains('deadline') || lower.contains('reminder') ||
        lower.contains('work') || lower.contains('job') || lower.contains('project') ||
        lower.contains('always') || lower.contains('never')) {
      return Importance.important;
    }
    if (lower.contains('like') || lower.contains('love') || lower.contains('hate') ||
        lower.contains('favourite') || lower.contains('favorite') ||
        lower.contains('prefer') || lower.contains('name') ||
        text.length < 20) {
      return Importance.normal;
    }
    return Importance.trivial;
  }

  Future<void> removeMatching(String query) async {
    final before = _entries.length;
    _entries.removeWhere((e) =>
      e.text.toLowerCase().contains(query.toLowerCase()) && e.importance != Importance.critical);
    await _save();
    _log.i('Removed ${before - _entries.length} entries matching "$query"');
  }

  Future<int> removeByCategory(String category) async {
    final before = _entries.length;
    _entries.removeWhere((e) =>
      e.type == MemoryType.preference &&
      _preferences.keys.any((k) => k == category) &&
      e.importance != Importance.critical);
    if (_preferences.containsKey(category)) _preferences.remove(category);
    await _save();
    final removed = before - _entries.length;
    if (removed > 0) _log.i('Removed $removed entries in category "$category"');
    return removed;
  }

  Future<void> clearAll() async {
    _entries.clear();
    _currentSession.clear();
    _preferences.clear();
    await _save();
    _log.i('All memory cleared');
  }

  List<MemoryEntry> getRecentFacts({int limit = 20}) {
    final sorted = List<MemoryEntry>.from(_entries)
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return sorted.where((e) => e.type == MemoryType.fact).take(limit).toList();
  }

  List<MemoryEntry> getRecentSessions({int limit = 5}) =>
    _entries.where((e) => e.type == MemoryType.session).take(limit).toList();

  List<MemoryEntry> search(String query, {int topK = 5}) {
    if (_entries.isEmpty) return [];
    final results = <_ScoredEntry>[];
    // entries without embeddings fall back to text similarity
    for (final entry in _entries) {
      if (entry.importance == Importance.trivial) continue;
      entry.accessCount++;
      final emb = entry.embedding;
      double score;
      if (emb != null && emb.length > 4) {
        // Use cached query embedding — compute once
        score = entry.relevanceScore;
      } else {
        score = _textSimilarity(query.toLowerCase(), entry.text.toLowerCase()) * 0.7 * entry.relevanceScore;
      }
      results.add(_ScoredEntry(entry, score));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(topK).where((e) => e.score > 0.1).map((e) => e.entry).toList();
  }

  String get contextPrompt {
    if (_entries.isEmpty && _preferences.isEmpty) return '';
    final parts = <String>[];

    final importantFacts = getRecentFacts(limit: 15);
    if (importantFacts.isNotEmpty) {
      parts.add('Things I know:');
      for (final f in importantFacts) {
        final marker = switch (f.importance) {
          Importance.critical => '!!',
          Importance.important => '!',
          _ => '-',
        };
        parts.add('$marker ${f.text}');
      }
    }

    if (_preferences.isNotEmpty) {
      parts.add('User preferences:');
      for (final e in _preferences.entries) {
        parts.add('- ${e.key}: ${e.value}');
      }
    }

    return parts.join('\n');
  }

  String getRelevantContext(String query) {
    if (query.isEmpty) return '';
    final results = search(query, topK: 5);
    if (results.isEmpty) return '';
    return 'Relevant memories:\n${results.map((e) => '- ${e.text}').join('\n')}';
  }

  Future<bool> autoSaveIfNeeded() async {
    _messageCount++;
    if (_messageCount >= _autoSaveInterval && _currentSession.length >= 2) {
      await saveSession();
      _messageCount = 0;
      return true;
    }
    return false;
  }

  Future<String?> learnFromConversation(String userMessage) async {
    final msg = userMessage.trim();

    final cmdResult = await _checkCommands(msg);
    if (cmdResult != null) return cmdResult;

    final correctionResult = _checkCorrection(msg);
    if (correctionResult != null) {
      await addFact(correctionResult, importance: Importance.important);
      return "Got it — I'll remember that instead.";
    }

    final learned = await _autoExtract(msg);
    if (learned != null) return learned;
    return null;
  }

  Future<String?> _checkCommands(String msg) async {
    final lower = msg.toLowerCase().trim();

    final rememberMatch = RegExp(r'^remember(?: that)?(?: i)?[:\s]+(.+)$', caseSensitive: false).firstMatch(msg);
    if (rememberMatch != null) {
      final fact = rememberMatch.group(1)!.trim();
      if (fact.isNotEmpty) {
        final imp = await addFact(fact);
        final label = switch (imp) {
          Importance.critical => "I'll never forget that.",
          Importance.important => "I've made a note of that.",
          _ => "OK, I'll remember that.",
        };
        return label;
      }
    }

    final forgetMatch = RegExp(r'^forget(?: about)? (?:the |my |that )?(.+)$', caseSensitive: false).firstMatch(msg);
    if (forgetMatch != null) {
      final target = forgetMatch.group(1)!.trim().toLowerCase();
      final totalBefore = _entries.length;
      removeMatching(target);
      for (final key in _preferences.keys.toList()) {
        if (key.toLowerCase().contains(target) || _preferences[key]!.toLowerCase().contains(target)) {
          _preferences.remove(key);
        }
      }
      final removed = totalBefore - _entries.length;
      if (removed > 0) {
        return "Forgot $removed thing${removed > 1 ? 's' : ''} about '$target'.";
      }
      return "I don't have any memory of '$target'.";
    }

    if (lower == 'what do you know' || lower == 'what do you know about me' ||
        lower == 'what do you remember' || lower == 'tell me what you know') {
      final facts = getRecentFacts(limit: 30);
      if (facts.isEmpty && _preferences.isEmpty) return "I don't know anything about you yet.";
      final lines = <String>[];
      for (final f in facts) {
        lines.add('• ${f.text}');
      }
      for (final e in _preferences.entries) {
        lines.add('• ${e.key}: ${e.value}');
      }
      return lines.isEmpty ? "Nothing significant to recall." : lines.join('\n');
    }

    if (lower.startsWith('what do you know about ')) {
      final topic = lower.replaceFirst('what do you know about ', '').trim();
      if (topic.isEmpty) return null;
      final results = search(topic, topK: 5);
      if (results.isEmpty) return "I don't know anything about '$topic'.";
      return 'What I know about "$topic":\n${results.map((e) => '- ${e.text}').join('\n')}';
    }

    return null;
  }

  String? _checkCorrection(String msg) {
    final patterns = [
      RegExp(r"no[.,]? (?:i |it'?s |that'?s )?(?:said |meant |was |is |actually )?(.+)$", caseSensitive: false),
      RegExp(r"actually[.,]? (?:i |it'?s |that'?s )?(.+)$", caseSensitive: false),
      RegExp(r"i (?:didn'?t say|don'?t|meant|meant to say) (?:that |it )?(.+)$", caseSensitive: false),
      RegExp(r"^(?:it'?s|that'?s) not (.+?),? (?:it'?s|it was|actually) (.+)$", caseSensitive: false),
      RegExp(r"^correction[:\s]+(.+)$", caseSensitive: false),
    ];

    for (final p in patterns) {
      final match = p.firstMatch(msg);
      if (match != null) {
        final correction = match.group(1)!.trim();
        if (correction.length > 5) return correction;
      }
    }
    return null;
  }

  Future<String?> _autoExtract(String msg) async {
    final lower = msg.toLowerCase().trim();
    final extractions = <String>[];

    if (lower.contains('my name is ') || lower.contains("i'm ") && !lower.contains("i'm going") && !lower.contains("i'm a")) {
      final patterns = [
        RegExp(r"my name is (\w+(?: \w+)?)", caseSensitive: false),
        RegExp(r"i'm (\w+(?: \w+)?)", caseSensitive: false),
        RegExp(r"call me (\w+(?: \w+)?)", caseSensitive: false),
      ];
      for (final p in patterns) {
        final match = p.firstMatch(msg);
        if (match != null && match.group(1)!.length > 1) {
          final name = match.group(1)!.trim();
          _preferences['name'] = name;
          extractions.add("User's name is $name");
          break;
        }
      }
    }

    final likeMatch = RegExp(r"i (?:really )?(?:like|love|enjoy) (.+)", caseSensitive: false).firstMatch(msg);
    if (likeMatch != null) {
      final thing = likeMatch.group(1)!.replaceAll(RegExp(r'\b(like|love|enjoy|that|it|and|to)\b'), '').trim();
      if (thing.isNotEmpty && thing.length > 3) {
        _preferences['likes'] = thing;
        extractions.add("User likes $thing");
      }
    }

    final hateMatch = RegExp(r"i (?:really )?(?:dislike|hate|don'?t like) (.+)", caseSensitive: false).firstMatch(msg);
    if (hateMatch != null) {
      final thing = hateMatch.group(1)!.replaceAll(RegExp(r'\b(that|it|and|to)\b'), '').trim();
      if (thing.isNotEmpty) {
        _preferences['dislikes'] = thing;
        extractions.add("User dislikes $thing");
      }
    }

    final liveMatch = RegExp(r"i live (?:in|at) (.+)", caseSensitive: false).firstMatch(msg);
    if (liveMatch != null) {
      final place = liveMatch.group(1)!.trim();
      _preferences['location'] = place;
      extractions.add("User lives $place");
    }

    final workMatch = RegExp(r"i work (?:at|as|for|in) (.+)", caseSensitive: false).firstMatch(msg);
    if (workMatch != null) {
      final work = workMatch.group(1)!.trim();
      _preferences['work'] = work;
      extractions.add("User works $work");
    }

    final haveMatch = RegExp(r"i have (?:a |an |my )?(.+)", caseSensitive: false).firstMatch(msg);
    if (haveMatch != null && !lower.contains('have to') && !lower.contains('have a question') && !lower.contains('i have a ')) {
      final thing = haveMatch.group(1)!.trim();
      if (thing.length > 4 && !thing.contains(' ')) {
        extractions.add("User has $thing");
      }
    }

    final prefMatch = RegExp(r"i (?:prefer|like it when) (.+)", caseSensitive: false).firstMatch(msg);
    if (prefMatch != null) {
      final pref = prefMatch.group(1)!.trim();
      extractions.add("User prefers $pref");
    }

    final dateMatch = RegExp(r"(?:my |our |the )?(birthday|anniversary|deadline|appointment|meeting)(?:\s+is\s+|\s+on\s+)(.+?)(?:\.|,|$)", caseSensitive: false).firstMatch(msg);
    if (dateMatch != null) {
      final event = dateMatch.group(1)!.trim();
      final date = dateMatch.group(2)!.trim();
      extractions.add("User's $event is $date");
    }

    for (final fact in extractions) {
      if (fact.isNotEmpty) {
        await addFact(fact);
      }
    }

    return extractions.isNotEmpty ? null : null;
  }

  void setPreference(String key, String value) {
    _preferences[key] = value;
  }

  String? getPreference(String key) => _preferences[key];

  double _textSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final aWords = a.split(RegExp(r'\s+')).toSet();
    final bWords = b.split(RegExp(r'\s+')).toSet();
    if (aWords.isEmpty || bWords.isEmpty) return 0;
    final intersection = aWords.intersection(bWords).length;
    return 2.0 * intersection / (aWords.length + bWords.length);
  }
}

class _ScoredEntry {
  final MemoryEntry entry;
  final double score;
  _ScoredEntry(this.entry, this.score);
}
