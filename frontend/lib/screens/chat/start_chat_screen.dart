import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/chat_service.dart';
import 'chat_screen.dart';

/// Two ways to start a chat: "Contact Support" jumps straight into a conversation with
/// the platform admin (no ID needed — every importer/exporter/logistics user can reach
/// admin support this way), or manually enter a trade partner's User ID for the
/// importer<->exporter / exporter<->logistics deal chats.
class StartChatScreen extends StatefulWidget {
  const StartChatScreen({super.key});
  @override
  State<StartChatScreen> createState() => _StartChatScreenState();
}

class _StartChatScreenState extends State<StartChatScreen> {
  final _idCtrl = TextEditingController();
  final _chatService = ChatService();
  bool _loading = false;
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

  Future<void> _start() async {
    if (_idCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final conversationId = await _chatService.startConversation(_idCtrl.text.trim());
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversationId, otherUserName: 'Chat')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                                Text('Contact Support', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('OR MESSAGE A TRADE PARTNER', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                  labelText: "Other User's ID",
                  helperText: 'Allowed between Importer↔Exporter or Exporter↔Logistics',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loading ? null : _start,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Start Conversation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
