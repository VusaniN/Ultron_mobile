import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ultron_mobile/core/injection_defense.dart';
import 'package:ultron_mobile/core/token_estimator.dart';
import 'package:ultron_mobile/providers/chat_provider.dart';
import 'package:ultron_mobile/providers/settings_provider.dart';
import 'package:ultron_mobile/services/agent_service.dart';
import 'package:ultron_mobile/services/device_service.dart';
import 'package:ultron_mobile/services/document_service.dart';
import 'package:ultron_mobile/services/embedding_service.dart';
import 'package:ultron_mobile/services/intent_service.dart';
import 'package:ultron_mobile/services/llm_service.dart';
import 'package:ultron_mobile/services/memory_service.dart';
import 'package:ultron_mobile/services/persona_service.dart';
import 'package:ultron_mobile/services/reflection_service.dart';
import 'package:ultron_mobile/services/sandbox_service.dart';
import 'package:ultron_mobile/services/skill_service.dart';
import 'package:ultron_mobile/services/tool_service.dart';
import 'package:ultron_mobile/services/voice_service.dart';
import 'package:ultron_mobile/app.dart';

Widget buildTestApp() {
  final voice = VoiceService();
  final device = DeviceService();
  final llm = LLMService();
  final embedding = EmbeddingService(apiKey: null);
  final memory = MemoryService(embeddings: embedding);
  final sandbox = SandboxService();
  final intent = IntentService();
  final persona = PersonaService();
  final defense = InjectionDefense();
  final tokenEstimator = TokenEstimator();
  final skills = SkillService();
  final documents = DocumentService();
  final reflector = ReflectionService();
  final toolService = ToolService(memory: memory, documents: documents, skills: skills, sandbox: sandbox);
  final agent = AgentService(tools: toolService, llm: llm);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => ChatProvider(
          voice: voice,
          device: device,
          llm: llm,
          memory: memory,
          sandbox: sandbox,
          intent: intent,
          persona: persona,
          defense: defense,
          tokenEstimator: tokenEstimator,
          skills: skills,
          documents: documents,
          reflector: reflector,
          agent: agent,
        ),
      ),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
    ],
    child: const UltronApp(),
  );
}

void main() {
  testWidgets('App renders ULTRON title', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());
    expect(find.text('ULTRON'), findsOneWidget);
    expect(find.text('ULTRON ready'), findsOneWidget);
  });

  testWidgets('App has text input field', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('App has mic button', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());
    expect(find.byType(GestureDetector), findsWidgets);
  });

  testWidgets('App has send button', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
