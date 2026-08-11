import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/chat_service.dart';

/// "AI Trade Assistant" — a stateless Q&A chat backed by the backend's Groq wrapper
/// (POST /chat/ai). Not a real conversation (no conversation row, no WebSocket, no
/// persistence) — the on-screen history lives only in this screen's local state, matching
/// "reuse infra without duplicating a conversation system". Bubble styling mirrors
/// ChatScreen's _MessageBubble as closely as possible for a consistent chat look.
class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});
  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIMessage {
  final String text;
  final bool isMine;
  const _AIMessage(this.text, this.isMine);
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final _chatService = ChatService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_AIMessage> _messages = [
    const _AIMessage(
      "Hi! I'm your OneBharat Trade Assistant. Ask me about import/export, RFQs, shipping, GST/IEC, HS codes, or how to use the platform.",
      false,
    ),
  ];
  bool _sending = false;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _inputCtrl.clear();
    setState(() {
      _messages.add(_AIMessage(text, true));
      _sending = true;
    });
    _scrollToBottom();
    try {
      final reply = await _chatService.askAI(text);
      if (mounted) setState(() => _messages.add(_AIMessage(reply, false)));
    } catch (e) {
      if (mounted) setState(() => _messages.add(_AIMessage('Sorry, the AI assistant is unavailable right now. ($e)', false)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Trade Assistant')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _AIBubble(message: _messages[i]),
            ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Typing…', style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic, fontSize: 12)),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      decoration: const InputDecoration(hintText: 'Ask about trade, RFQs, shipping...', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send, color: AppColors.primary), onPressed: _sending ? null : _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same look as ChatScreen's _MessageBubble (colors, padding, radius) for a consistent feel.
class _AIBubble extends StatelessWidget {
  final _AIMessage message;
  const _AIBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final bg = message.isMine ? AppColors.primary : Colors.white;
    final fg = message.isMine ? Colors.white : AppColors.textPrimary;
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: message.isMine ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: Text(message.text, style: TextStyle(color: fg)),
      ),
    );
  }
}
