import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants/app_constants.dart';
import '../core/network/api_client.dart';
import '../models/chat.dart';

class ChatService {
  final ApiClient _client = ApiClient();

  Future<String> startConversation(String otherUserId) async {
    final res = await _client.post('/chat/conversations', data: {'other_user_id': otherUserId});
    return res.data['data']['id'];
  }

  /// Resolves the platform admin's user id so "Contact Support" doesn't require the
  /// user to know an admin's ID — then starts (or reuses) that conversation directly.
  Future<Map<String, String>> getSupportContact() async {
    final res = await _client.get('/chat/support-contact');
    final data = res.data['data'];
    return {'user_id': data['user_id'] as String, 'full_name': data['full_name'] as String};
  }

  Future<List<ConversationSummary>> listConversations() async {
    final res = await _client.get('/chat/conversations');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ConversationSummary.fromJson(e)).toList();
  }

  /// Returned newest-first by the backend — reverse for a chronological chat view.
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final res = await _client.get('/chat/conversations/$conversationId/messages');
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ChatMessage.fromJson(e)).toList().reversed.toList();
  }

  Future<ChatMessage> sendMessageRest({
    required String conversationId,
    required String type,
    String? content,
    String? fileUrl,
    String? quotationId,
  }) async {
    final res = await _client.post('/chat/conversations/$conversationId/messages', data: {
      'type': type,
      'content': content,
      'file_url': fileUrl,
      'quotation_id': quotationId,
    });
    return ChatMessage.fromJson(res.data['data']);
  }

  Future<void> markRead(String conversationId) async {
    await _client.post('/chat/conversations/$conversationId/read');
  }
}

/// Wraps a single WebSocket connection for the lifetime of an open chat screen.
/// Falls back to nothing automatically — callers should use [ChatService.sendMessageRest]
/// if [isConnected] is false when they need to send.
class ChatSocket {
  WebSocketChannel? _channel;
  final _storage = const FlutterSecureStorage();
  final _incoming = StreamController<ChatMessage>.broadcast();

  Stream<ChatMessage> get messages => _incoming.stream;
  bool get isConnected => _channel != null;

  Future<void> connect() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    if (token == null) return;

    _channel = WebSocketChannel.connect(Uri.parse('${AppConstants.chatWsUrl}?token=$token'));
    _channel!.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
          if (decoded['type'] == 'message' && decoded['data'] != null) {
            _incoming.add(ChatMessage.fromJson(decoded['data']));
          }
        } catch (_) {
          // ignore malformed frames
        }
      },
      onDone: () => _channel = null,
      onError: (_) => _channel = null,
      cancelOnError: true,
    );
  }

  void send({
    required String conversationId,
    required String type,
    String? content,
    String? fileUrl,
    String? quotationId,
  }) {
    _channel?.sink.add(jsonEncode({
      'conversation_id': conversationId,
      'type': type,
      'content': content,
      'file_url': fileUrl,
      'quotation_id': quotationId,
    }));
  }

  void dispose() {
    _channel?.sink.close();
    _incoming.close();
  }
}
