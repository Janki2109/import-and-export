import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/chat_service.dart';
import 'ai_assistant_screen.dart';
import 'chat_screen.dart';

/// Chat entry point — exactly two options: "Help & Support" (jumps straight into a
/// conversation with the platform admin — every importer/exporter/logistics user can reach
/// support this way) and "AI Trade Assistant" (Groq-backed Q&A, see ai_assistant_screen.dart).
/// Direct trade-partner-to-trade-partner messaging has been removed — the backend's
/// ChatService.allowedPair now only allows a user<->admin pair either way, so this screen no
/// longer offers a raw "Other User's ID" option.
class StartChatScreen extends StatefulWidget {
  const StartChatScreen({super.key});
  @override
  State<StartChatScreen> createState() => _StartChatScreenState();
}

class _StartChatScreenState extends State<StartChatScreen> {
  final _chatService = ChatService();
  bool _loadingSupport = false;

  Future<void> _contactSupport() async {
    setState(() => _loadingSupport = true);
    try {
      final admin = await _chatService.getSupportContact();
      final conversationId = await _chatService.startConversation(admin['user_id']!);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversationId, otherUserName: admin['full_name'] ?? 'Support')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loadingSupport = false);
    }
  }

  void _openAIAssistant() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AIAssistantScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Chat')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.support_agent_outlined, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Help & Support', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                Text('Chat directly with the OneBharat team', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loadingSupport ? null : _contactSupport,
                          icon: _loadingSupport
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const Text('Chat with Support'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.smart_toy_outlined, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AI Trade Assistant', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                Text('Get instant answers on trade, RFQs, shipping & more', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openAIAssistant,
                          icon: const Icon(Icons.smart_toy_outlined, size: 18),
                          label: const Text('Ask AI Trade Assistant'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
