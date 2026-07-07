class Persona {
  final String id;
  final String name;
  final String description;
  final String systemPromptAddon;
  final Map<String, String> config;

  const Persona({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPromptAddon,
    this.config = const {},
  });

  static const List<Persona> builtIn = [
    Persona(
      id: 'ultron_default',
      name: 'ULTRON',
      description: 'Sharp, efficient, slightly dry wit',
      systemPromptAddon: '',
    ),
    Persona(
      id: 'ultron_professional',
      name: 'ULTRON Pro',
      description: 'Formal, precise, business-oriented',
      systemPromptAddon: 'Speak formally and professionally. Be precise and data-driven. Avoid slang and humor.',
    ),
    Persona(
      id: 'ultron_friendly',
      name: 'ULTRON Friend',
      description: 'Warm, casual, conversational',
      systemPromptAddon: 'Be warm and friendly. Use casual language. Ask follow-up questions. Be encouraging.',
    ),
    Persona(
      id: 'ultron_minimal',
      name: 'ULTRON Minimal',
      description: 'One-sentence answers, no fluff',
      systemPromptAddon: 'Answer in one sentence maximum. No greetings, no sign-offs, no extra text.',
    ),
    Persona(
      id: 'ultron_teacher',
      name: 'ULTRON Teacher',
      description: 'Explains concepts in detail',
      systemPromptAddon: 'Explain concepts thoroughly as if teaching a beginner. Use examples and analogies. Be patient.',
    ),
    Persona(
      id: 'ultron_dev',
      name: 'ULTRON Dev',
      description: 'Technical, code-focused assistant',
      systemPromptAddon: 'Focus on technical accuracy. Provide code examples when relevant. Assume the user is a developer.',
    ),
  ];

  static Persona defaultPersona = builtIn.first;

  String buildSystemPrompt(String basePrompt) {
    if (systemPromptAddon.isEmpty) return basePrompt;
    return '$basePrompt\n\nAdditional style guide: $systemPromptAddon';
  }
}
