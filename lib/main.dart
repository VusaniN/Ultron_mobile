import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'core/logger.dart';
import 'core/secure_storage.dart';
import 'core/token_estimator.dart';
import 'core/injection_defense.dart';
import 'services/voice_service.dart';
import 'services/device_service.dart';
import 'services/llm_service.dart';
import 'services/memory_service.dart';
import 'services/sandbox_service.dart';
import 'services/intent_service.dart';
import 'services/persona_service.dart';
import 'services/skill_service.dart';
import 'services/document_service.dart';
import 'services/reflection_service.dart';
import 'services/embedding_service.dart';
import 'services/tool_service.dart';
import 'services/agent_service.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'app.dart';

final Logger _log = Logger('Main');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Logger.setMinLevel(LogLevel.debug);
  _log.i('Starting ULTRON Mobile...');

  try {
    await dotenv.load(fileName: '.env');
    _log.i('Environment loaded');
  } catch (e) {
    _log.w('No .env file found, using defaults: $e');
  }

  final secure = SecureStorage();
  await secure.init();

  final voice = VoiceService();
  final device = DeviceService();
  final llm = LLMService();
  final openRouterKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
  final embedding = EmbeddingService(apiKey: dotenv.env['GOOGLE_API_KEY']);
  embedding.init(openRouterKey: openRouterKey);
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
  final settings = SettingsProvider();
  await settings.load();

  if (settings.currentModelId != 'qwen/qwen3-coder:free') {
    llm.switchModel(settings.currentModelId);
  }

  _validateApiKeys(secure);

  try {
    await memory.init();
    _log.i('Memory loaded');
  } catch (e) {
    _log.w('Memory init failed: $e');
  }

  try {
    final voiceAvailable = await voice.init();
    _log.i('Voice initialized: $voiceAvailable');
  } catch (e) {
    _log.w('Voice init failed: $e');
  }

  try {
    await persona.init();
    _log.i('Persona service initialized');
  } catch (e) {
    _log.w('Persona init failed: $e');
  }

  try {
    await skills.init();
  } catch (e) {
    _log.w('Skills init failed: $e');
  }

  runApp(
    MultiProvider(
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
            settings: settings,
          ),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => settings,
        ),
      ],
      child: const UltronApp(),
    ),
  );

  _log.i('ULTRON Mobile started');
}

void _validateApiKeys(SecureStorage secure) {
  final googleKey = dotenv.env['GOOGLE_API_KEY'] ?? '';
  final elevenKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
  final openRouterKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';

  if (googleKey.isEmpty || googleKey == 'your_gemini_api_key_here') {
    _log.w('GOOGLE_API_KEY not set — Gemini models unavailable');
  } else if (!googleKey.startsWith('AIza')) {
    _log.w('GOOGLE_API_KEY format looks wrong (starts with "${googleKey.substring(0, 3)}" instead of "AIza") — Gemini may fail');
  }

  if (elevenKey.isEmpty || elevenKey == 'your_key_here') {
    _log.w('ELEVENLABS_API_KEY not set — premium voice unavailable');
  } else {
    _log.d('ElevenLabs API key present, checking credits...');
  }

  if (openRouterKey.isEmpty || openRouterKey == 'your_key_here') {
    _log.w('OPENROUTER_API_KEY not set — most LLMs unavailable');
  }
}
