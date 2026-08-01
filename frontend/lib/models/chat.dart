class ConversationSummary {
  final String id;
  final String otherUserId;
  final String otherUserName;
  final String otherUserRole;
  final String? lastMessagePreview;
  final int unreadCount;
  final DateTime? lastMessageAt;

  ConversationSummary({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserRole,
    this.lastMessagePreview,
    required this.unreadCount,
    this.lastMessageAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) => ConversationSummary(
        id: json['id'],
        otherUserId: json['other_user_id'],
        otherUserName: json['other_user_name'],
        otherUserRole: json['other_user_role'],
        lastMessagePreview: json['last_message_preview'],
        unreadCount: json['unread_count'] ?? 0,
        lastMessageAt: json['last_message_at'] != null ? DateTime.parse(json['last_message_at']) : null,
      );
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String type; // text, file, document, quotation
  final String? content;
  final String? fileUrl;
  final String? quotationId;
  final bool isRead;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    this.content,
    this.fileUrl,
    this.quotationId,
    required this.isRead,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        conversationId: json['conversation_id'],
        senderId: json['sender_id'],
        type: json['type'],
        content: json['content'],
        fileUrl: json['file_url'],
        quotationId: json['quotation_id'],
        isRead: json['is_read'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );
}
