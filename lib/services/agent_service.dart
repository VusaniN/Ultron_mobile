import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/logger.dart';
import '../models/tool.dart';
import 'tool_service.dart';
import 'llm_service.dart';

class AgentService {
  final Logger _log = Logger('AgentService');
  final ToolService tools;
  final LLMService llm;
  bool _thinking = false;

  AgentService({required this.tools, required this.llm});

  bool get isThinking => _thinking;

  Stream<String> process(List<Map<String, dynamic>> messages) async* {
    _thinking = true;
    try {
      final toolDefs = tools.allowedTools;
      var currentMessages = List<Map<String, dynamic>>.from(messages);
      int iterations = 0;
      const maxIterations = 5;

      while (iterations < maxIterations) {
        iterations++;
        _log.d('Agent iteration $iterations, messages: ${currentMessages.length}');

        final response = await _callWithTools(currentMessages, toolDefs);

        if (response == null) {
          _log.e('Agent: LLM returned null');
          break;
        }

        final toolCalls = response['tool_calls'] as List?;
        final content = response['content'] as String?;

        if (toolCalls != null && toolCalls.isNotEmpty) {
          currentMessages.add({
            'role': 'assistant',
            'content': content ?? '',
            'tool_calls': toolCalls,
          });

          for (final tc in toolCalls) {
            final callId = tc['id'] as String? ?? '';
            final fn = tc['function'] as Map?;
            if (fn == null) continue;
            final name = fn['name'] as String? ?? '';
            final args = fn['arguments'] as String? ?? '{}';
            Map<String, dynamic> parsedArgs = {};
            try {
              parsedArgs = jsonDecode(args) as Map<String, dynamic>;
            } catch (_) {}

            _log.d('Agent calling tool: $name($parsedArgs)');
            final result = await tools.execute(name, parsedArgs);
            if (result.output is String && (result.output as String).startsWith('NEEDS_CONFIRMATION:')) {
              final toolName = (result.output as String).split(':').last;
              currentMessages.add({
                'role': 'tool',
                'content': 'The tool "$toolName" requires your approval. Ask the user if they want to proceed before running it.',
                'tool_call_id': callId,
              });
              yield '[THINK] Tool "$toolName" needs confirmation — asking user...[/THINK]\n';
              continue;
            }
            currentMessages.add(ToolResult(toolName: result.toolName, output: result.output, isError: result.isError, callId: callId).toMessage());
          }
          // Yield thinking indicator
          yield '[THINK] Executed ${toolCalls.length} tool(s), processing results...[/THINK]\n';
        } else if (content != null && content.isNotEmpty) {
          // Final response — stream it
          // First, add the assistant message
          currentMessages.add({'role': 'assistant', 'content': content});

          // If streaming supported, get the streaming version; otherwise yield content
          yield* _streamResponse(content);
          break;
        } else {
          _log.w('Agent: empty response, breaking');
          break;
        }
      }

      if (iterations >= maxIterations) {
        yield '[THINK] Reached maximum reasoning depth, summarizing...[/THINK]\n';
        final summary = await _getFinalResponse(currentMessages);
        yield* _streamResponse(summary ?? 'I apologize, but I was unable to complete that analysis in the available time.');
      }
    } catch (e) {
      _log.e('Agent error: $e');
      yield 'Error in agent processing: $e';
    } finally {
      _thinking = false;
    }
  }

  Future<Map<String, dynamic>?> _callWithTools(
    List<Map<String, dynamic>> messages,
    List<ToolDefinition> toolDefs,
  ) async {
    try {
      final body = {
        'messages': messages,
        'tools': toolDefs.map((t) => t.toOpenRouterSpec()).toList(),
        'tool_choice': 'auto',
      };

      final key = await llm.getApiKey('OPENROUTER_API_KEY');
      if (key.isEmpty) return null;

      final res = await http.post(
        Uri.parse(llm.apiUrl),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          ...llm.extraHeaders,
        },
        body: jsonEncode({
          ...body,
          'model': llm.currentModel,
          'max_tokens': 2048,
        }),
      ).timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        _log.e('Agent API error ${res.statusCode}: ${res.body}');
        return null;
      }

      final data = jsonDecode(res.body);
      final choice = data['choices']?[0];
      if (choice == null) return null;

      final message = choice['message'] as Map<String, dynamic>?;
      return message;
    } catch (e) {
      _log.e('Agent API call failed: $e');
      return null;
    }
  }

  Stream<String> _streamResponse(String content) async* {
    if (content.isEmpty) return;
    // Real streaming: build messages and stream from OpenRouter SSE
    final key = await llm.getApiKey('OPENROUTER_API_KEY');
    if (key.isEmpty) {
      yield content;
      return;
    }
    try {
      final request = http.Request('POST', Uri.parse(llm.apiUrl));
      request.headers.addAll({
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
        ...llm.extraHeaders,
        'Accept': 'text/event-stream',
      });
      request.body = jsonEncode({
        'model': llm.currentModel,
        'messages': [{'role': 'user', 'content': 'Continue naturally from: $content'}],
        'max_tokens': 512,
        'temperature': 0.7,
        'stream': true,
      });
      final response = await http.Client().send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        yield content;
        return;
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
              final chunk = delta?['content'] as String?;
              if (chunk != null && chunk.isNotEmpty) yield chunk;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      _log.d('SSE streaming failed, falling back to direct output: $e');
      yield content;
    }
  }

  Future<String?> _getFinalResponse(List<Map<String, dynamic>> messages) async {
    try {
      final key = await llm.getApiKey('OPENROUTER_API_KEY');
      if (key.isEmpty) return null;

      final res = await http.post(
        Uri.parse(llm.apiUrl),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          ...llm.extraHeaders,
        },
        body: jsonEncode({
          'model': llm.currentModel,
          'messages': [
            {'role': 'system', 'content': 'Provide a concise summary of your findings and final answer to the user based on the conversation so far.'},
            ...messages,
          ],
          'max_tokens': 1024,
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['choices']?[0]?['message']?['content'] as String?;
      }
    } catch (e) {
      _log.e('Final response error: $e');
    }
    return null;
  }
}
