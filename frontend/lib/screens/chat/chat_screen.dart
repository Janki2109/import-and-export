import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../../core/theme/app_theme.dart';
import '../../models/chat.dart';
import '../../models/trade.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../services/chat_service.dart';
import '../../services/trade_service.dart';
import '../../services/upload_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherUserName;
  // Journey 8 — online status: optional so existing call sites that don't have this handy
  // keep working unchanged; the presence dot just doesn't show without it.
  final String? otherUserId;
  const ChatScreen({super.key, required this.conversationId, required this.otherUserName, this.otherUserId});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _chatService = ChatService();
  final _tradeService = TradeService();
  final _uploadService = UploadService();
  final _socket = ChatSocket();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _recorder = AudioRecorder();
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _recording = false;
  bool _uploadingVoice = false;
  // Journey 8 — typing indicator / online status / read receipts.
  bool _otherTyping = false;
  bool _otherOnline = false;
  DateTime? _lastTypingSent;

  @override
  void initState() {
    super.initState();
    _init();
    _inputCtrl.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    // Throttle to at most one typing event per 2s — no need to spam the socket per keystroke.
    final now = DateTime.now();
    if (_lastTypingSent == null || now.difference(_lastTypingSent!) > const Duration(seconds: 2)) {
      _lastTypingSent = now;
      _socket.sendTyping(widget.conversationId);
    }
  }

  Future<void> _init() async {
    try {
      final history = await _chatService.listMessages(widget.conversationId);
      if (mounted) setState(() => _messages.addAll(history));
      await _chatService.markRead(widget.conversationId);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    await _socket.connect();
    _socket.messages.listen((msg) {
      if (msg.conversationId == widget.conversationId && mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
        // A new incoming message while this screen is open counts as read immediately.
        if (msg.senderId != ref.read(authProvider).currentUser?.id) {
          _chatService.markRead(widget.conversationId);
        }
      }
    });
    _socket.typingEvents.listen((event) {
      if (event['conversation_id'] == widget.conversationId && mounted) {
        setState(() => _otherTyping = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _otherTyping = false);
        });
      }
    });
    if (widget.otherUserId != null) {
      _socket.presenceEvents.listen((event) {
        if (event['user_id'] == widget.otherUserId && mounted) {
          setState(() => _otherOnline = event['online'] as bool? ?? false);
        }
      });
    }
    _socket.readReceipts.listen((conversationId) {
      if (conversationId == widget.conversationId && mounted) {
        final myId = ref.read(authProvider).currentUser?.id;
        setState(() {
          for (var i = 0; i < _messages.length; i++) {
            if (_messages[i].senderId == myId && !_messages[i].isRead) {
              _messages[i] = _messages[i].copyWithRead(true);
            }
          }
        });
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();

    if (_socket.isConnected) {
      _socket.send(conversationId: widget.conversationId, type: 'text', content: text);
      // Optimistic local echo — the real persisted copy arrives back over the socket too,
      // but showing it immediately keeps the UI feeling instant.
    } else {
      try {
        final msg = await _chatService.sendMessageRest(conversationId: widget.conversationId, type: 'text', content: text);
        if (mounted) setState(() => _messages.add(msg));
        _scrollToBottom();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _shareQuotation() async {
    try {
      final quotations = await _tradeService.listMyQuotations();
      if (!mounted) return;
      final picked = await showModalBottomSheet<Quotation>(
        context: context,
        builder: (_) => ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: quotations.isEmpty
              ? [const Text('No quotations to share yet.', style: TextStyle(color: AppColors.textSecondary))]
              : quotations
                  .map((q) => ListTile(
                        title: Text('₹${q.unitPrice.toStringAsFixed(2)}/unit · ${q.status}'),
                        subtitle: Text('Total: ₹${q.totalAmount.toStringAsFixed(2)}'),
                        onTap: () => Navigator.pop(context, q),
                      ))
                  .toList(),
        ),
      );
      if (picked == null) return;

      if (_socket.isConnected) {
        _socket.send(conversationId: widget.conversationId, type: 'quotation', quotationId: picked.id, content: 'Shared a quotation');
      } else {
        final msg = await _chatService.sendMessageRest(conversationId: widget.conversationId, type: 'quotation', quotationId: picked.id, content: 'Shared a quotation');
        if (mounted) setState(() => _messages.add(msg));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _shareDocumentLink() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Document Link'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Paste a document/file URL', labelText: 'File URL'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Share')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;

    if (_socket.isConnected) {
      _socket.send(conversationId: widget.conversationId, type: 'document', fileUrl: url, content: 'Shared a document');
    } else {
      try {
        final msg = await _chatService.sendMessageRest(conversationId: widget.conversationId, type: 'document', fileUrl: url, content: 'Shared a document');
        if (mounted) setState(() => _messages.add(msg));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null) return;
      await _sendVoiceNote(path);
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is required for voice notes.')));
      return;
    }
    final dir = await Directory.systemTemp.createTemp('voice_note');
    final path = '${dir.path}/note.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() => _recording = true);
  }

  Future<void> _sendVoiceNote(String path) async {
    setState(() => _uploadingVoice = true);
    try {
      final fileUrl = await _uploadService.uploadFile(category: 'chat', file: File(path), contentType: 'audio/mp4');
      if (_socket.isConnected) {
        _socket.send(conversationId: widget.conversationId, type: 'voice', fileUrl: fileUrl, content: 'Voice note');
      } else {
        final msg = await _chatService.sendMessageRest(conversationId: widget.conversationId, type: 'voice', fileUrl: fileUrl, content: 'Voice note');
        if (mounted) setState(() => _messages.add(msg));
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _uploadingVoice = false);
    }
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _socket.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.read(authProvider).currentUser?.id;
    final myRole = ref.read(authProvider).currentUser?.role;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUserName),
        bottom: widget.otherUserId == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: _otherOnline ? AppColors.success : AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(_otherOnline ? 'Online' : 'Offline', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet. Say hello!', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final isMine = m.senderId == myUserId;
                          return _MessageBubble(message: m, isMine: isMine);
                        },
                      ),
          ),
          if (_otherTyping)
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
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.attach_file),
                    onSelected: (v) {
                      if (v == 'quotation') _shareQuotation();
                      if (v == 'document') _shareDocumentLink();
                    },
                    itemBuilder: (context) => [
                      if (myRole == UserRole.exporter)
                        const PopupMenuItem(value: 'quotation', child: Text('Share Quotation')),
                      const PopupMenuItem(value: 'document', child: Text('Share Document Link')),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      decoration: const InputDecoration(hintText: 'Type a message', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  if (_uploadingVoice)
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  else
                    IconButton(
                      icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none_outlined, color: _recording ? AppColors.error : AppColors.textSecondary),
                      tooltip: _recording ? 'Stop recording' : 'Record voice note',
                      onPressed: _toggleRecording,
                    ),
                  IconButton(icon: const Icon(Icons.send, color: AppColors.primary), onPressed: _sendText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? AppColors.primary : Colors.white;
    final fg = isMine ? Colors.white : AppColors.textPrimary;

    Widget content;
    switch (message.type) {
      case 'quotation':
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.request_quote_outlined, size: 18, color: fg),
            const SizedBox(width: 6),
            Text('Quotation shared', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ],
        );
        break;
      case 'voice':
        content = _VoicePlayer(fileUrl: message.fileUrl, color: fg);
        break;
      case 'document':
      case 'file':
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 18, color: fg),
            const SizedBox(width: 6),
            Flexible(child: Text(message.content ?? 'Document shared', style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
          ],
        );
        break;
      default:
        content = Text(message.content ?? '', style: TextStyle(color: fg));
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: isMine ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            content,
            // Journey 8 — read receipts: only shown on my own sent messages, mirroring the
            // familiar single/double-tick convention.
            if (isMine) ...[
              const SizedBox(height: 2),
              Icon(message.isRead ? Icons.done_all : Icons.done, size: 14, color: fg.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoicePlayer extends StatefulWidget {
  final String? fileUrl;
  final Color color;
  const _VoicePlayer({required this.fileUrl, required this.color});

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<void> _toggle() async {
    if (widget.fileUrl == null) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(UrlSource(widget.fileUrl!));
      setState(() => _playing = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: widget.color, size: 28),
          onPressed: _toggle,
        ),
        const SizedBox(width: 6),
        Text('Voice note', style: TextStyle(color: widget.color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
