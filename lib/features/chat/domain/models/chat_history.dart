import 'chat_message.dart';

class ChatHistory {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime timestamp;

  ChatHistory({
    required this.id,
    required this.title,
    required this.messages,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatHistory.fromJson(Map<String, dynamic> json) {
    return ChatHistory(
      id: json['id'],
      title: json['title'],
      messages: (json['messages'] as List)
          .map((m) => ChatMessage.fromJson(m))
          .toList(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
