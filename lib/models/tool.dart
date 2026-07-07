import 'dart:convert';

class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  Map<String, dynamic> toOpenRouterSpec() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };
}

class ToolResult {
  final String toolName;
  final dynamic output;
  final bool isError;
  final String? callId;

  const ToolResult({required this.toolName, required this.output, this.isError = false, this.callId});

  Map<String, dynamic> toMessage() => {
    'role': 'tool',
    'content': isError ? 'Error: $output' : jsonEncode(output),
    if (callId != null) 'tool_call_id': callId,
  };
}
