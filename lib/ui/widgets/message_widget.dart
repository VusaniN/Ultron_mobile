import 'package:flutter/material.dart';
import '../../models/message.dart';

class MessageWidget extends StatelessWidget {
  final Message message;
  final bool isStreaming;

  const MessageWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isBot = message.sender == 'bot';
    final isSystem = message.sender == 'system';
    final isThought = message.sender == 'thought';

    if (isSystem) {
      return _systemBubble();
    }
    if (isThought) {
      return _thoughtBubble();
    }
    return _chatBubble(context, isBot);
  }

  Widget _systemBubble() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      child: Text(
        message.text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _thoughtBubble() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFFF2A5E).withOpacity(0.15),
          ),
        ),
        child: Text(
          message.text,
          style: const TextStyle(
            color: Color(0xFFFF8A9E),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _chatBubble(BuildContext context, bool isBot) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isBot ? const Color(0xFF1A1A2E) : const Color(0xFF2A2A4E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isBot
                ? const Color(0xFFFF2A5E).withOpacity(0.3)
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isBot ? const Color(0xFFE0E0E0) : Colors.white,
                fontSize: 14,
              ),
            ),
            if (isStreaming)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFF2A5E),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
