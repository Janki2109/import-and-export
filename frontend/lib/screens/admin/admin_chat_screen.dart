import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../models/chat.dart';
import '../../services/admin_service.dart';
import '../../widgets/admin_ui_kit.dart';

/// Chat Management — every conversation on the platform, with both participants, last
/// message, and status. View Conversation reads messages read-only (admin isn't a
/// participant, so this bypasses the normal participant-only restriction — admin-only,
/// read-only). Archive toggles the new is_archived column; Block User reuses the existing
/// is_active suspend mechanism, since that's the real thing that stops someone logging in.
class AdminChatScreen extends StatefulWidget {
  const AdminChatScreen({super.key});
  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final _adminService = AdminService();
  late Future<List<AdminConversationRow>> _future;
  String _query = '';
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _future = _adminService.listConversations();
  }

  void _refresh() => setState(() => _future = _adminService.listConversations());

  Future<void> _archive(AdminConversationRow c, bool archived) async {
    try {
      await _adminService.archiveConversation(c.id, archived);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(archived ? 'Conversation archived' : 'Conversation unarchived'), backgroundColor: AppColors.success));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _blockUser(String userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Block User'),
        content: Text('Block $userName? This deactivates their account (same as Suspend in User Management) — they will not be able to log in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _adminService.blockUser(userId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$userName blocked'), backgroundColor: AppColors.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _viewConversation(AdminConversationRow c) async {
    final messages = await _adminService.getConversationMessages(c.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) {
          final parsed = messages.map((m) => ChatMessage.fromJson(m)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Expanded(child: Text('${c.userAName} ↔ ${c.userBName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    IconButton(
                      icon: Icon(c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, size: 20),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _archive(c, !c.isArchived);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: parsed.isEmpty
                    ? const AdminEmptyState(icon: Icons.forum_outlined, title: 'No messages yet.')
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: parsed.length,
                        itemBuilder: (context, i) {
                          final m = parsed[parsed.length - 1 - i];
                          final isA = m.senderId == c.userAId;
                          return Align(
                            alignment: isA ? Alignment.centerLeft : Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              constraints: const BoxConstraints(maxWidth: 280),
                              decoration: BoxDecoration(
                                color: isA ? Colors.grey.shade100 : AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isA ? c.userAName : c.userBName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                                  const SizedBox(height: 2),
                                  Text(m.content ?? '[${m.type}]', style: const TextStyle(fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(m.createdAt.toLocal().toString().split('.').first, style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminGradientAppBar(title: 'Chat Management'),
      body: AdminPageBackground(
        child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<AdminConversationRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
            }
            final all = snapshot.data ?? [];
            final filtered = all.where((c) {
              if (!_showArchived && c.isArchived) return false;
              if (_query.trim().isEmpty) return true;
              final q = _query.trim().toLowerCase();
              return c.userAName.toLowerCase().contains(q) || c.userBName.toLowerCase().contains(q);
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: AdminSearchField(
                    hint: 'Search by participant name',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Show archived', style: TextStyle(fontSize: 12.5)),
                      Switch(value: _showArchived, onChanged: (v) => setState(() => _showArchived = v)),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const AdminEmptyState(icon: Icons.chat_bubble_outline, title: 'No conversations found.')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            return AdminReveal(
                              index: i,
                              child: AdminCard(
                                accent: const Color(0xFF7C3AED),
                                onTap: () => _viewConversation(c),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text('${c.userAName} (${c.userARole}) ↔ ${c.userBName} (${c.userBRole})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                          if (c.isArchived)
                                            const AdminStatusBadge(label: 'Archived', color: Colors.grey),
                                        ],
                                      ),
                                      if ((c.userAEmail ?? '').isNotEmpty || (c.userBEmail ?? '').isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          [if ((c.userAEmail ?? '').isNotEmpty) c.userAEmail!, if ((c.userBEmail ?? '').isNotEmpty) c.userBEmail!].join(' · '),
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(c.lastMessagePreview ?? 'No messages yet', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text('${c.messageCount} messages · ${c.lastMessageAt?.toLocal().toString().split(' ').first ?? c.createdAt.toLocal().toString().split(' ').first}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _viewConversation(c),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                              icon: const Icon(Icons.visibility_outlined, size: 14),
                                              label: const Text('View', style: TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _archive(c, !c.isArchived),
                                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 8)),
                                              icon: Icon(c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, size: 14),
                                              label: Text(c.isArchived ? 'Unarchive' : 'Archive', style: const TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: PopupMenuButton<String>(
                                              onSelected: (uid) => _blockUser(uid, uid == c.userAId ? c.userAName : c.userBName),
                                              itemBuilder: (context) => [
                                                PopupMenuItem(value: c.userAId, child: Text('Block ${c.userAName}')),
                                                PopupMenuItem(value: c.userBId, child: Text('Block ${c.userBName}')),
                                              ],
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                                decoration: BoxDecoration(border: Border.all(color: AppColors.error), borderRadius: BorderRadius.circular(12)),
                                                child: const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.block, size: 14, color: AppColors.error),
                                                    SizedBox(width: 4),
                                                    Text('Block', style: TextStyle(fontSize: 12, color: AppColors.error)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        ),
      ),
    );
  }
}
