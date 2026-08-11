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

  /// AI Trade Assistant — stateless request/response via the backend's Groq wrapper. The
  /// GROQ_API_KEY itself never reaches the client; only the reply text does.
  Future<String> askAI(String message) async {
    final res = await _client.post('/chat/ai', data: {'message': message});
    return res.data['data']['reply'] as String;
  }
}

/// Wraps a single WebSocket connection for the lifetime of an open chat screen.
/// Falls back to nothing automatically — callers should use [ChatService.sendMessageRest]
/// if [isConnected] is false when they need to send.
class ChatSocket {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  final _storage = const FlutterSecureStorage();
  final _incoming = StreamController<ChatMessage>.broadcast();
  // Journey 8 — typing indicator / online status: (conversationId, userId) for typing,
  // (userId, online) for presence. Kept as raw maps rather than new model classes since
  // these are ephemeral UI signals, not persisted domain data.
  final _typing = StreamController<Map<String, String>>.broadcast();
  final _presence = StreamController<Map<String, dynamic>>.broadcast();
  final _readReceipts = StreamController<String>.broadcast();
  final _errors = StreamController<String>.broadcast();

  Stream<ChatMessage> get messages => _incoming.stream;
  Stream<Map<String, String>> get typingEvents => _typing.stream;
  Stream<Map<String, dynamic>> get presenceEvents => _presence.stream;
  /// Emits the conversation_id whose messages the other participant just read.
  Stream<String> get readReceipts => _readReceipts.stream;
  /// Emits error messages surfaced by the backend over the socket (type == 'error'), e.g.
  /// a rejected send — so callers can fall back to REST or show feedback.
  Stream<String> get errorStream => _errors.stream;
  /// True only once the WebSocket connection is actually established (channel created and
  /// not yet closed/errored) — not merely "connect() was called".
  bool get isConnected => _connected && _channel != null;

  Future<void> connect() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    if (token == null) return;

    final channel = WebSocketChannel.connect(Uri.parse('${AppConstants.chatWsUrl}?token=$token'));
    _channel = channel;
    try {
      // `ready` completes once the WebSocket handshake has actually succeeded; it throws if
      // the connection fails outright, so isConnected never reports true for a dead socket.
      await channel.ready;
      _connected = true;
    } catch (_) {
      _connected = false;
      _channel = null;
      return;
    }

    _subscription = channel.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
          switch (decoded['type']) {
            case 'message':
              if (decoded['data'] != null) _incoming.add(ChatMessage.fromJson(decoded['data']));
              break;
            case 'typing':
              _typing.add({
                'conversation_id': decoded['conversation_id'] as String? ?? '',
                'user_id': decoded['user_id'] as String? ?? '',
              });
              break;
            case 'presence':
              _presence.add({
                'user_id': decoded['user_id'] as String? ?? '',
                'online': decoded['online'] as bool? ?? false,
              });
              break;
            case 'read':
              _readReceipts.add(decoded['conversation_id'] as String? ?? '');
              break;
            case 'error':
              _errors.add(decoded['message'] as String? ?? decoded['error'] as String? ?? 'Unknown chat error');
              break;
          }
        } catch (_) {
          // ignore malformed frames
        }
      },
      onDone: () {
        _connected = false;
        _channel = null;
      },
      onError: (_) {
        _connected = false;
        _channel = null;
      },
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

  /// Journey 8 — typing indicator: a lightweight, non-persisted WS event. The backend
  /// forwards it to the other participant only; nothing is stored.
  void sendTyping(String conversationId) {
    _channel?.sink.add(jsonEncode({'conversation_id': conversationId, 'type': 'typing'}));
  }

  void dispose() {
    _subscription?.cancel();
    _connected = false;
    _channel?.sink.close();
    _incoming.close();
    _typing.close();
    _presence.close();
    _readReceipts.close();
    _errors.close();
  }
}
