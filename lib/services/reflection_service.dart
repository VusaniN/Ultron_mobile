import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/logger.dart';
import '../core/secure_storage.dart';

class ReflectionResult {
  final List<String> facts;
  final List<String> preferences;
  final List<String> potentialSkills;
  final String? userState;

  ReflectionResult({
    this.facts = const [],
    this.preferences = const [],
    this.potentialSkills = const [],
    this.userState,
  });

  bool get isEmpty => facts.isEmpty && preferences.isEmpty && potentialSkills.isEmpty;
}

class ReflectionService {
  final Logger _log = Logger('ReflectionService');
  final SecureStorage _secure = SecureStorage();

  Future<ReflectionResult> reflect(String userMessage, String? aiResponse) async {
    try {
      final apiKey = await _secure.read('OPENROUTER_API_KEY');
      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_key_here') {
        return ReflectionResult();
      }

      final text = aiResponse != null ? 'User: $userMessage\nAssistant: $aiResponse' : userMessage;

      final res = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'meta-llama/llama-3.3-70b-instruct:free',
          'messages': [
            {
              'role': 'system',
              'content': '''Extract information from this conversation turn. Return ONLY valid JSON with these fields:
{
  "facts": ["list of facts to remember about the user or topic"],
  "preferences": ["user preferences expressed"],
  "potentialSkills": ["any skill the user would find useful based on this conversation"],
  "userState": "mood or state of the user (e.g. curious, frustrated, happy, busy)"
}
If nothing to extract, return {"facts":[],"preferences":[],"potentialSkills":[],"userState":null}
Be thorough but only extract what's directly supported by the text.'''
            },
            {'role': 'user', 'content': text},
          ],
          'max_tokens': 300,
          'temperature': 0.3,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return ReflectionResult();

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final content = (data['choices'] as List).first['message']['content'] as String? ?? '';
      final cleaned = content.replaceAll(RegExp(r'```json\s*|\s*```'), '').trim();
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

      return ReflectionResult(
        facts: (parsed['facts'] as List?)?.cast<String>() ?? [],
        preferences: (parsed['preferences'] as List?)?.cast<String>() ?? [],
        potentialSkills: (parsed['potentialSkills'] as List?)?.cast<String>() ?? [],
        userState: parsed['userState'] as String?,
      );
    } catch (e) {
      _log.d('Reflection skipped: $e');
      return ReflectionResult();
    }
  }
}
