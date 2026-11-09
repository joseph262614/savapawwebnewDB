import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

class AdminAdopterMessagesScreen extends StatefulWidget {
  final bool embeddedMode;

  const AdminAdopterMessagesScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminAdopterMessagesScreen> createState() => _AdminAdopterMessagesScreenState();
}

class _AdminAdopterMessagesScreenState extends State<AdminAdopterMessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();

  String? _selectedChatId;
  Map<String, dynamic>? _selectedChatData;
  bool _isSending = false;

  @override
  void dispose() {
    _searchController.dispose();
    _replyController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messagesScrollController.hasClients) {
        _messagesScrollController.animateTo(
          _messagesScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Recent';
    int millis = 0;
    if (timestamp is num) {
      millis = timestamp.toInt();
    } else if (timestamp is String) {
      millis = int.tryParse(timestamp) ?? 0;
    }
    if (millis == 0) return 'Recent';

    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  void _selectChat(String chatId, Map<String, dynamic> data) {
    setState(() {
      _selectedChatId = chatId;
      _selectedChatData = data;
    });

    // Mark as read in user_chats
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseDatabase.instance
          .ref()
          .child('user_chats')
          .child(user.uid)
          .child(chatId)
          .update({'unread': false});
    }

    _scrollToBottom();
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSending || _selectedChatId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final otherUid = (_selectedChatData?['otherUid'] ?? '').toString();

    setState(() => _isSending = true);
    _replyController.clear();

    try {
      final db = FirebaseDatabase.instance.ref();

      // 1. Push to chats/$chatId/messages
      final msgRef = db.child('chats').child(_selectedChatId!).child('messages').push();
      await msgRef.set({
        'senderUid': user.uid,
        'senderName': 'Save-A-Paws Admin',
        'text': text,
        'timestamp': ServerValue.timestamp,
      });

      // 2. Update chats/$chatId parent record
      await db.child('chats').child(_selectedChatId!).update({
        'lastMessage': text,
        'lastTimestamp': ServerValue.timestamp,
        'lastSenderUid': user.uid,
      });

      // 3. Update admin's user_chats
      await db.child('user_chats').child(user.uid).child(_selectedChatId!).update({
        'lastMessage': text,
        'lastTimestamp': ServerValue.timestamp,
        'lastSenderUid': user.uid,
        'unread': false,
      });

      // 4. Update adopter's user_chats
      if (otherUid.isNotEmpty) {
        await db.child('user_chats').child(otherUid).child(_selectedChatId!).update({
          'lastMessage': text,
          'lastTimestamp': ServerValue.timestamp,
          'lastSenderUid': user.uid,
          'unread': true,
        });
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Error sending admin reply: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reply: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;

        return Column(
          children: [
            // Header banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0288D1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF0288D1), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Messages',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Direct communication with adopters inquiring about shelter pets and handovers',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Two-Pane Workspace
            Expanded(
              child: Row(
                children: [
                  // Left Pane: Conversation List
                  SizedBox(
                    width: isDesktop ? 360 : 300,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(right: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Column(
                        children: [
                          // Search field
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search by adopter or pet...',
                                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                                filled: true,
                                fillColor: const Color(0xFFF8F9FA),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade200),
                                ),
                              ),
                            ),
                          ),

                          // Conversation Items
                          Expanded(
                            child: user == null
                                ? const Center(child: Text('Please log in'))
                                : StreamBuilder<DatabaseEvent>(
                                    stream: FirebaseDatabase.instance
                                        .ref()
                                        .child('user_chats')
                                        .child(user.uid)
                                        .onValue,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(color: AppTheme.primaryOrange),
                                        );
                                      }

                                      final List<Map<String, dynamic>> conversations = [];

                                      if (snapshot.hasData && snapshot.data?.snapshot.value is Map) {
                                        final map = snapshot.data!.snapshot.value as Map;
                                        map.forEach((k, v) {
                                          if (v is Map) {
                                            final item = Map<String, dynamic>.from(v);
                                            item['chatId'] = k.toString();
                                            conversations.add(item);
                                          }
                                        });
                                      }

                                      // Sort: newest first
                                      conversations.sort((a, b) {
                                        final tA = (a['lastTimestamp'] ?? 0) is num ? (a['lastTimestamp'] ?? 0) as num : 0;
                                        final tB = (b['lastTimestamp'] ?? 0) is num ? (b['lastTimestamp'] ?? 0) as num : 0;
                                        return tB.compareTo(tA);
                                      });

                                      final query = _searchController.text.trim().toLowerCase();
                                      final filtered = conversations.where((c) {
                                        if (query.isEmpty) return true;
                                        final otherName = (c['otherName'] ?? '').toString().toLowerCase();
                                        final petName = (c['petName'] ?? '').toString().toLowerCase();
                                        final lastMsg = (c['lastMessage'] ?? '').toString().toLowerCase();
                                        return otherName.contains(query) || petName.contains(query) || lastMsg.contains(query);
                                      }).toList();

                                      if (filtered.isEmpty) {
                                        return Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24.0),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade300),
                                                const SizedBox(height: 12),
                                                Text(
                                                  query.isEmpty
                                                      ? 'No adopter inquiries yet'
                                                      : 'No conversations matching "$query"',
                                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      return ListView.separated(
                                        itemCount: filtered.length,
                                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                                        itemBuilder: (context, index) {
                                          final c = filtered[index];
                                          final chatId = (c['chatId'] ?? '').toString();
                                          final isSelected = chatId == _selectedChatId;
                                          final otherName = (c['otherName'] ?? 'Adopter').toString();
                                          final petName = (c['petName'] ?? '').toString();
                                          final petImage = (c['petImage'] ?? '').toString();
                                          final lastMsg = (c['lastMessage'] ?? '').toString();
                                          final timeStr = _formatTimestamp(c['lastTimestamp']);
                                          final unread = c['unread'] == true;

                                          return InkWell(
                                            onTap: () => _selectChat(chatId, c),
                                            child: Container(
                                              color: isSelected ? AppTheme.primaryOrange.withValues(alpha: 0.08) : Colors.transparent,
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Pet Avatar
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: SizedBox(
                                                      width: 44,
                                                      height: 44,
                                                      child: _buildMiniAvatar(petImage),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // Details
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                otherName,
                                                                style: TextStyle(
                                                                  fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                                                                  fontSize: 13.5,
                                                                  color: const Color(0xFF2D3142),
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                            Text(
                                                              timeStr,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: unread ? AppTheme.primaryOrange : Colors.grey.shade500,
                                                                fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        if (petName.isNotEmpty) ...[
                                                          const SizedBox(height: 2),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                            decoration: BoxDecoration(
                                                              color: Colors.orange.shade50,
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                            child: Text(
                                                              'Inquiring: $petName',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.orange.shade800,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          lastMsg.isEmpty ? 'Started inquiry' : lastMsg,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: unread ? Colors.black87 : Colors.grey.shade600,
                                                            fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (unread) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      margin: const EdgeInsets.only(top: 6),
                                                      decoration: const BoxDecoration(
                                                        color: AppTheme.primaryOrange,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Right Pane: Active Chat Conversation
                  Expanded(
                    child: _selectedChatId == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                const Text(
                                  'Select an adopter conversation',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Chat live with prospective adopters to review requirements and schedule handovers',
                                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          )
                        : _buildChatThreadPane(user),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (widget.embeddedMode) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      body: content,
    );
  }

  Widget _buildChatThreadPane(User? currentUser) {
    final otherName = (_selectedChatData?['otherName'] ?? 'Adopter').toString();
    final petName = (_selectedChatData?['petName'] ?? 'Shelter Pet').toString();
    final petImage = (_selectedChatData?['petImage'] ?? '').toString();

    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(
        children: [
          // Active Chat Top Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: _buildMiniAvatar(petImage),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            otherName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2D3142)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Adopter',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Inquiring about: $petName',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Message history stream
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref()
                  .child('chats')
                  .child(_selectedChatId!)
                  .child('messages')
                  .orderByChild('timestamp')
                  .onValue,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
                }

                final List<Map<String, dynamic>> messages = [];
                if (snapshot.hasData && snapshot.data?.snapshot.value is Map) {
                  final map = snapshot.data!.snapshot.value as Map;
                  map.forEach((k, v) {
                    if (v is Map) {
                      final m = Map<String, dynamic>.from(v);
                      m['id'] = k.toString();
                      messages.add(m);
                    }
                  });
                }

                messages.sort((a, b) {
                  final tA = (a['timestamp'] ?? 0) is num ? (a['timestamp'] ?? 0) as num : 0;
                  final tB = (b['timestamp'] ?? 0) is num ? (b['timestamp'] ?? 0) as num : 0;
                  return tA.compareTo(tB);
                });

                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages in this inquiry yet. Say hello!',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _messagesScrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['senderUid'] == currentUser?.uid;
                    final text = (msg['text'] ?? '').toString();
                    final timeStr = _formatTimestamp(msg['timestamp']);

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        constraints: const BoxConstraints(maxWidth: 480),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? AppTheme.primaryOrange : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(isMe ? 14 : 2),
                            bottomRight: Radius.circular(isMe ? 2 : 14),
                          ),
                          border: Border.all(
                            color: isMe ? AppTheme.primaryOrange : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: isMe ? Colors.white : const Color(0xFF2D3142),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe ? Colors.white70 : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Message Input Toolbar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    onSubmitted: (_) => _sendReply(),
                    decoration: InputDecoration(
                      hintText: 'Type an official reply to $otherName...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: const Color(0xFFF8F9FA),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: AppTheme.primaryOrange,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _isSending ? null : _sendReply,
                    tooltip: 'Send Reply',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAvatar(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.pets, color: Colors.grey, size: 22),
      );
    }
    if (imageUrl.startsWith('data:image')) {
      try {
        final commaIdx = imageUrl.indexOf(',');
        final base64Str = commaIdx != -1 ? imageUrl.substring(commaIdx + 1) : imageUrl;
        return Image.memory(base64Decode(base64Str), fit: BoxFit.cover);
      } catch (_) {
        return Container(color: Colors.grey.shade200, child: const Icon(Icons.broken_image));
      }
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.broken_image)),
    );
  }
}

