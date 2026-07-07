class Message {
  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isStreaming;

  const Message({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
  });

  Message copyWith({
    String? id,
    String? sender,
    String? text,
    DateTime? timestamp,
    bool? isStreaming,
  }) {
    return Message(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender': sender,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    sender: json['sender'] as String,
    text: json['text'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

enum Sender { user, bot, system, thought }

extension SenderExt on String {
  Sender toSender() {
    switch (this) {
      case 'user': return Sender.user;
      case 'bot': return Sender.bot;
      case 'system': return Sender.system;
      case 'thought': return Sender.thought;
      default: return Sender.bot;
    }
  }
}
