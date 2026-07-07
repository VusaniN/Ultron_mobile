import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/message.dart';
import '../../models/persona.dart';
import '../../providers/chat_provider.dart';
import '../../services/llm_service.dart';
import '../../services/memory_service.dart';
import '../widgets/message_widget.dart';
import '../widgets/thinking_indicator.dart';
import '../widgets/sphere_painter.dart';
import '../widgets/pulse_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _sphereController;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _sphereController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _sphereController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _textFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _onSubmit(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();
    final provider = context.read<ChatProvider>();
    await provider.handleTextInput(text);
  }

  void _showPersonaSelector(BuildContext context) {
    final provider = context.read<ChatProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final personas = provider.persona.allPersonas;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Persona',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: personas.map((p) => _personaTile(ctx, p, provider)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _personaTile(BuildContext ctx, Persona p, ChatProvider provider) {
    final isSelected = provider.persona.current.id == p.id;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? const Color(0xFFFF2A5E) : Colors.white38,
      ),
      title: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(p.description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      onTap: () {
        provider.persona.switchPersona(p.id);
        provider.addSystemMessage('Switched to ${p.name} persona.');
        Navigator.pop(ctx);
      },
    );
  }

  void _showModelSelector(BuildContext context) {
    final provider = context.read<ChatProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Model',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: LLMService.availableModels.map((m) => _modelTile(ctx, m, provider)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _modelTile(BuildContext ctx, ModelConfig m, ChatProvider provider) {
    final isSelected = provider.llm.currentModelId == m.id;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? const Color(0xFFFF2A5E) : Colors.white38,
      ),
      title: Text(
        m.label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        m.isFree ? 'Free' : '\$${m.costPer1kTokens}/1K tokens',
        style: TextStyle(
          color: m.isFree ? const Color(0xFF00FF9D) : Colors.white54,
          fontSize: 11,
        ),
      ),
      onTap: () {
        provider.llm.switchModel(m.id);
        provider.addSystemMessage('Switched to ${m.label}.');
        Navigator.pop(ctx);
      },
    );
  }

  void _showMicSettings(BuildContext context, ChatProvider provider) {
    final voice = provider.voice;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text(
                    'Microphone Settings',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _micSettingTile(
                    'Push-to-Talk',
                    'Hold Space to talk, release to send. Best for echo suppression.',
                    Icons.mic,
                    provider.pushToTalk,
                    () {
                      if (!provider.pushToTalk) {
                        provider.togglePushToTalk();
                        setSheetState(() {});
                      }
                    },
                    () {
                      if (provider.pushToTalk) {
                        provider.togglePushToTalk();
                        setSheetState(() {});
                      }
                    },
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  _micSettingTile(
                    'Wake Word',
                    'Say "${voice.wakeWord}" to activate. Continuous listening.',
                    Icons.radar,
                    provider.autoListen,
                    () {
                      provider.togglePushToTalk();
                      provider.toggleAutoListen();
                      setSheetState(() {});
                    },
                    () {},
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),
                  const Text('Listening Duration', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Slider(
                    value: voice.listenDuration.inSeconds.toDouble(),
                    min: 10,
                    max: 300,
                    divisions: 29,
                    activeColor: const Color(0xFFFF2A5E),
                    inactiveColor: Colors.white12,
                    label: '${voice.listenDuration.inSeconds}s',
                    onChanged: (v) {
                      voice.setListenDuration(Duration(seconds: v.toInt()));
                      setSheetState(() {});
                    },
                  ),
                  Text('${voice.listenDuration.inSeconds}s max listen',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 8),
                  const Text('Pause Threshold', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Slider(
                    value: voice.pauseDuration.inSeconds.toDouble(),
                    min: 1,
                    max: 15,
                    divisions: 14,
                    activeColor: const Color(0xFFFF2A5E),
                    inactiveColor: Colors.white12,
                    label: '${voice.pauseDuration.inSeconds}s',
                    onChanged: (v) {
                      voice.setPauseDuration(Duration(seconds: v.toInt()));
                      setSheetState(() {});
                    },
                  ),
                  Text('${voice.pauseDuration.inSeconds}s silence = end of speech',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 12),
                  const Text('Speech Locale', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    value: voice.currentLocale,
                    dropdownColor: const Color(0xFF2A2A4E),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: voice.availableLocales.map((l) {
                      return DropdownMenuItem(
                        value: l.localeId,
                        child: Text('${l.localeId} — ${l.name}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) voice.setLocale(v);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Mic: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(
                        voice.isListening ? 'ACTIVE' : 'IDLE',
                        style: TextStyle(
                          color: voice.isListening ? const Color(0xFF00FF9D) : Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('Speech API: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(
                        voice.isSpeechAvailable ? 'READY' : 'UNAVAILABLE',
                        style: TextStyle(
                          color: voice.isSpeechAvailable ? const Color(0xFF00FF9D) : const Color(0xFFFF2A5E),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        provider.listenOnce();
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2A5E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Test Microphone'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
    );
  }

  Widget _micSettingTile(String title, String subtitle, IconData icon, bool enabled, VoidCallback onEnable, VoidCallback onDisable) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: enabled ? const Color(0xFFFF2A5E) : Colors.white38),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      trailing: Switch(
        value: enabled,
        activeColor: const Color(0xFFFF2A5E),
        inactiveTrackColor: Colors.white12,
        onChanged: (v) => v ? onEnable() : onDisable(),
      ),
    );
  }

  void _toggleSandbox(ChatProvider provider) {
    provider.sandbox.toggleChatOnly();
    provider.addSystemMessage(
      provider.sandbox.chatOnly
          ? 'Sandbox active — Ultron is restricted to chat only.'
          : 'Sandbox off — device commands allowed.',
    );
  }

  void _showSkillsPanel(BuildContext context) {
    final provider = context.read<ChatProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final skills = provider.skills.skills;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Skills', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Say "teach skill [name]" to create one, or type in chat.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              if (skills.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text("No skills yet.", style: TextStyle(color: Colors.white38)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: skills.map((s) => ListTile(
                      dense: true,
                      title: Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text('${s.triggers.join(", ")} • ${s.useCount} uses',
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                        onPressed: () {
                          provider.skills.forget(s.name);
                          provider.addSystemMessage("Forgot skill '${s.name}'.");
                          Navigator.pop(ctx);
                        },
                      ),
                    )).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showDocumentReader(BuildContext context) {
    final provider = context.read<ChatProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final controller = TextEditingController();
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Read a Document', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Enter the full file path or type "read [path]" in chat.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'C:\\path\\to\\file.txt',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF2A2A4E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    provider.handleTextInput('read $value');
                    Navigator.pop(ctx);
                  }
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      provider.handleTextInput('read ${controller.text.trim()}');
                      Navigator.pop(ctx);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2A5E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Read'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Supported: .txt .md .csv .log .json .yaml .xml .html\nMax file size: 10 MB',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMemoryPanel(BuildContext context) {
    final provider = context.read<ChatProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final facts = provider.memory.getRecentFacts(limit: 50);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Memory', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('${facts.length} facts', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Things I know about you. Tap X to forget something.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 12),
              if (facts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text("I don't know anything about you yet. Talk to me and I'll learn.",
                      style: TextStyle(color: Colors.white38)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: facts.length,
                    itemBuilder: (context, i) {
                      final f = facts[i];
                      final badge = switch (f.importance) {
                        Importance.critical => '!!',
                        Importance.important => '!',
                        _ => '•',
                      };
                      final badgeColor = switch (f.importance) {
                        Importance.critical => const Color(0xFFFF2A5E),
                        Importance.important => const Color(0xFFE8A857),
                        _ => Colors.white38,
                      };
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
                        leading: Text(badge, style: TextStyle(color: badgeColor, fontSize: 16, fontWeight: FontWeight.bold)),
                        title: Text(f.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text(
                          '${f.createdAt.day}/${f.createdAt.month}/${f.createdAt.year}',
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.white24),
                          onPressed: () {
                            provider.memory.removeMatching(f.text);
                            provider.addSystemMessage("Forgot: ${f.text.substring(0, f.text.length.clamp(0, 40))}...");
                            Navigator.pop(ctx);
                          },
                        ),
                      );
                    },
                  ),
                ),
              if (facts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        provider.memory.clearAll();
                        provider.addSystemMessage('All memory cleared.');
                        Navigator.pop(ctx);
                      },
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFD9736F)),
                      child: const Text('Clear all memory', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: (event) {
        final provider = context.read<ChatProvider>();
        if (!provider.pushToTalk) return;
        if (event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            provider.pushToTalkStart();
          } else if (event is KeyUpEvent) {
            provider.pushToTalkEnd();
          }
        }
      },
      child: GestureDetector(
        onTap: () => _keyboardFocus.requestFocus(),
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                _buildHeader(),
                const SizedBox(height: 10),
                _buildChatList(),
                _buildApprovalBar(),
                _buildInputBar(),
                _buildMicButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 80,
              width: 80,
              child: AnimatedBuilder(
                animation: _sphereController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: SpherePainter(
                      phase: _sphereController.value * 2 * 3.14159,
                      accentColor: const Color(0xFFFF2A5E),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'ULTRON',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    if (provider.persona.current.id != 'ultron_default')
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2A5E).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          provider.persona.current.name.replaceFirst('ULTRON ', ''),
                          style: const TextStyle(
                            color: Color(0xFFFF2A5E),
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      provider.status == ChatStatus.thinking
                          ? 'Thinking...'
                          : provider.statusText,
                      style: TextStyle(
                        color: provider.status == ChatStatus.thinking
                            ? const Color(0xFFFF2A5E)
                            : const Color(0xFF00FF9D),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ThinkingIndicator(
                      isThinking: provider.status == ChatStatus.thinking,
                    ),
                    if (provider.apiCallsThisSession > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '${provider.apiCallsThisSession} calls · ${provider.totalTokensThisSession}t',
                          style: const TextStyle(color: Colors.white24, fontSize: 9, fontFamily: 'IBM Plex Mono'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            _iconButton(
              Icons.person_outline,
              'Persona: ${provider.persona.current.name}',
              () => _showPersonaSelector(context),
            ),
            _iconButton(
              Icons.auto_awesome,
              'Model: ${provider.currentModelLabel}',
              () => _showModelSelector(context),
            ),
            _iconButton(
              Icons.tune,
              'Mic settings',
              () => _showMicSettings(context, provider),
              active: provider.pushToTalk || provider.autoListen,
            ),
            _iconButton(
              Icons.psychology,
              'Show thinking',
              provider.toggleThoughts,
              active: provider.showThoughts,
            ),
            _iconButton(
              Icons.auto_fix_high,
              'Skills (${provider.skills.skills.length})',
              () => _showSkillsPanel(context),
            ),
            _iconButton(
              Icons.memory,
              'Memory',
              () => _showMemoryPanel(context),
            ),
            _iconButton(
              Icons.description,
              'Read a document',
              () => _showDocumentReader(context),
            ),
            _iconButton(
              Icons.shield,
              'Sandbox',
              () => _toggleSandbox(provider),
              active: provider.sandbox.chatOnly,
            ),
            _iconButton(
              Icons.delete_outline,
              'Clear chat',
              provider.clearChat,
            ),
          ],
        );
      },
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onPressed, {bool active = false}) {
    return IconButton(
      icon: Icon(
        icon,
        color: active ? const Color(0xFFFF2A5E) : Colors.white38,
        size: 20,
      ),
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildChatList() {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        return Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: provider.messages.length,
            itemBuilder: (context, index) {
              final msg = provider.messages[index];
              return MessageWidget(
                message: msg,
                isStreaming: msg.isStreaming,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildApprovalBar() {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        if (!provider.hasPendingAction) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A4E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFF2A5E).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Color(0xFFFF2A5E), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  provider.pendingActionText ?? 'Allow this action?',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: provider.denyPendingAction,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD9736F),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                ),
                child: const Text('Deny', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: provider.alwaysAllowPendingAction,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9AA3B2),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Always allow', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: provider.confirmPendingAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF9D),
                  foregroundColor: const Color(0xFF12151C),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Allow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _textFocus,
              onSubmitted: _onSubmit,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: "Ask Ultron anything...",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFFFF2A5E),
            radius: 22,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: () => _onSubmit(_textController.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: PulseButton(
            isListening: provider.isActive,
            onTap: provider.toggleVoice,
            activeColor: const Color(0xFFFF2A5E),
            inactiveColor: const Color(0xFF2A2A4E),
          ),
        );
      },
    );
  }
}

extension _ProviderLabel on ChatProvider {
  String get currentModelLabel {
    final id = llm.currentModelId;
    final match = LLMService.availableModels.where((m) => m.id == id);
    return match.isNotEmpty ? match.first.label : id.split('/').last;
  }
}
