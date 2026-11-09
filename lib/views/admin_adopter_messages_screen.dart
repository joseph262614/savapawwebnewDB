import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      final db = FirebaseDatabase.instance.ref();
      db.child('user_chats')
          .child(user.uid)
          .child(chatId)
          .update({'unread': false}).catchError((_) {});

      final otherUid = (data['otherUid'] ?? '').toString();
      final petId = (data['petId'] ?? '').toString();

      db.child('system_messages')
          .child(user.uid)
          .get()
          .then((snap) {
        if (snap.exists && snap.value is Map) {
          final msgs = snap.value as Map;
          msgs.forEach((k, v) {
            if (v is Map) {
              final replyToUid = v['replyToUid']?.toString();
              final pId = v['petId']?.toString();
              if (replyToUid == otherUid || (petId.isNotEmpty && pId == petId)) {
                if (v['read'] != true) {
                  db.child('system_messages')
                      .child(user.uid)
                      .child(k.toString())
                      .update({'read': true}).catchError((_) {});
                }
              }
            }
          });
        }
      }).catchError((_) {});
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
        final isCompact = constraints.maxWidth < 650;

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
                  if (!isCompact || _selectedChatId == null)
                    Expanded(
                      flex: isCompact ? 1 : 0,
                      child: SizedBox(
                        width: isCompact ? double.infinity : (isDesktop ? 360 : 300),
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
                ),

                  // Right Pane: Active Chat Conversation
                  if (!isCompact || _selectedChatId != null)
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
                          : _buildChatThreadPane(user, isCompact: isCompact),
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

  Widget _buildChatThreadPane(User? currentUser, {bool isCompact = false}) {
    final otherUid = (_selectedChatData?['otherUid'] ?? '').toString();
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
                if (isCompact) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3142)),
                    tooltip: 'Back to conversations',
                    onPressed: () => setState(() => _selectedChatId = null),
                  ),
                  const SizedBox(width: 8),
                ],
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
                      StreamBuilder<DatabaseEvent>(
                        stream: FirebaseDatabase.instance.ref().child('users').child(otherUid).onValue,
                        builder: (context, userSnap) {
                          String roleLabel = 'Adopter';
                          Color badgeBg = Colors.blue.shade50;
                          Color badgeColor = Colors.blue.shade700;

                          if (userSnap.hasData && userSnap.data?.snapshot.value is Map) {
                            final uData = Map<String, dynamic>.from(userSnap.data!.snapshot.value as Map);
                            final role = (uData['role'] ?? '').toString().toLowerCase();
                            final bool isUserAdmin = uData['isAdmin'] == true || role == 'admin';
                            if (isUserAdmin) {
                              roleLabel = 'Staff / Admin';
                              badgeBg = Colors.purple.shade50;
                              badgeColor = Colors.purple.shade700;
                            } else if (role == 'foster' || role == 'partner' || role == 'rescue partner') {
                              roleLabel = 'Foster';
                              badgeBg = Colors.teal.shade50;
                              badgeColor = Colors.teal.shade700;
                            } else if (role == 'volunteer') {
                              roleLabel = 'Volunteer';
                              badgeBg = Colors.orange.shade50;
                              badgeColor = Colors.orange.shade800;
                            }
                          }

                          return Row(
                            children: [
                              Text(
                                otherName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2D3142)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  roleLabel,
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: badgeColor),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 2),
                      StreamBuilder<DatabaseEvent>(
                        stream: FirebaseDatabase.instance.ref().child('users').child(otherUid).onValue,
                        builder: (context, userSnap) {
                          String sub = 'Inquiring about: $petName';
                          if (userSnap.hasData && userSnap.data?.snapshot.value is Map) {
                            final uData = Map<String, dynamic>.from(userSnap.data!.snapshot.value as Map);
                            final role = (uData['role'] ?? '').toString().toLowerCase();
                            final bool isUserAdmin = uData['isAdmin'] == true || role == 'admin';
                            if (isUserAdmin) {
                              sub = 'Shelter Admin • Chatting about: $petName';
                            } else if (role == 'foster' || role == 'partner' || role == 'rescue partner') {
                              sub = 'Foster for $petName';
                            }
                          }
                          return Text(
                            sub,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Adoption Process & Pass Header Card
          _buildAdoptionProcessHeader(currentUser),

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

  Widget _buildAdoptionProcessHeader(User? currentUser) {
    final otherUid = (_selectedChatData?['otherUid'] ?? '').toString();
    final petId = (_selectedChatData?['petId'] ?? '').toString();
    final petName = (_selectedChatData?['petName'] ?? 'Shelter Pet').toString();
    final otherName = (_selectedChatData?['otherName'] ?? 'Adopter').toString();

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('adoption_inquiries').onValue,
      builder: (context, snap) {
        String? inquiryId;
        Map<String, dynamic>? inquiryData;

        if (snap.hasData && snap.data?.snapshot.value is Map) {
          final map = snap.data!.snapshot.value as Map;

          // 1. Match both petId and otherUid
          for (final entry in map.entries) {
            if (entry.value is Map) {
              final inq = Map<String, dynamic>.from(entry.value as Map);
              final inqPet = (inq['petId'] ?? '').toString();
              final inqAdopter = (inq['adopterUid'] ?? '').toString();
              final inqFoster = (inq['fosterId'] ?? '').toString();

              if (petId.isNotEmpty && petId != 'general' && inqPet == petId) {
                if (inqAdopter == otherUid || inqFoster == otherUid) {
                  inquiryId = entry.key.toString();
                  inquiryData = inq;
                  break;
                }
              }
            }
          }

          // 2. Match by petId
          if (inquiryData == null && petId.isNotEmpty && petId != 'general') {
            for (final entry in map.entries) {
              if (entry.value is Map) {
                final inq = Map<String, dynamic>.from(entry.value as Map);
                if ((inq['petId'] ?? '').toString() == petId) {
                  inquiryId = entry.key.toString();
                  inquiryData = inq;
                  break;
                }
              }
            }
          }

          // 3. Match by otherUid
          if (inquiryData == null && otherUid.isNotEmpty) {
            for (final entry in map.entries) {
              if (entry.value is Map) {
                final inq = Map<String, dynamic>.from(entry.value as Map);
                if ((inq['adopterUid'] ?? '').toString() == otherUid || (inq['fosterId'] ?? '').toString() == otherUid) {
                  inquiryId = entry.key.toString();
                  inquiryData = inq;
                  break;
                }
              }
            }
          }
        }

        if (inquiryData == null) {
          return const SizedBox.shrink();
        }

        final status = (inquiryData['status']?.toString() ?? 'pending').toLowerCase();
        final adopterAgreed = inquiryData['adopterAgreedTerms'] == true;
        final adoptionCode = (inquiryData['adoptionCode']?.toString() ?? '').toUpperCase().trim();
        final scheduledDate = (inquiryData['scheduledPickupDate']?.toString() ?? '').trim();
        final bool isHandoverCompleted = status == 'completed' ||
            inquiryData['isHandedOver'] == true ||
            inquiryData['petRetrieved'] == true ||
            inquiryData['handoverCompletedAt'] != null;

        return _buildAdoptionStatusBar(
          inquiryId: inquiryId!,
          inquiryData: inquiryData,
          status: status,
          adopterAgreed: adopterAgreed,
          adoptionCode: adoptionCode,
          scheduledDate: scheduledDate,
          isHandoverCompleted: isHandoverCompleted,
          petId: petId,
          petName: petName,
          otherName: otherName,
          otherUid: otherUid,
        );
      },
    );
  }

  Widget _buildAdoptionStatusBar({
    required String inquiryId,
    required Map<String, dynamic> inquiryData,
    required String status,
    required bool adopterAgreed,
    required String adoptionCode,
    required String scheduledDate,
    required bool isHandoverCompleted,
    required String petId,
    required String petName,
    required String otherName,
    required String otherUid,
  }) {
    final String inqAdopterUid = (inquiryData['adopterUid'] ?? '').toString();
    final String inqAdopterName = (inquiryData['adopterName'] ?? '').toString();
    final String inqFosterId = (inquiryData['fosterId'] ?? '').toString();
    final bool isChattingWithFoster = inqFosterId.isNotEmpty && inqFosterId == otherUid;
    final String displayAdopterName = inqAdopterName.isNotEmpty ? inqAdopterName : (isChattingWithFoster ? 'Applicant' : otherName);

    // 1. Cancelled State
    if (status == 'cancelled') {
      final reason = inquiryData['cancellationReason']?.toString() ?? 'Adoption was cancelled.';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: Colors.red.shade50,
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, size: 18, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Adoption Cancelled: $reason',
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade800, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Pending Review
    if (status == 'pending' && !adopterAgreed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border(bottom: BorderSide(color: Colors.amber.shade300)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
              child: Icon(Icons.pending_actions, size: 18, color: Colors.amber.shade900),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step 1 of 4: Adoption Inquiry Pending Review',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                  ),
                  Text(
                    isChattingWithFoster
                        ? 'Chatting with Foster $otherName. Applicant $displayAdopterName is awaiting approval for $petName.'
                        : '$displayAdopterName has submitted an inquiry to adopt $petName. Mark as approved to initiate the agreement process.',
                    style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!isChattingWithFoster || inqAdopterUid.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () => _handleApproveAdopter(
                  inquiryId,
                  petId,
                  petName,
                  displayAdopterName,
                  inqAdopterUid.isNotEmpty ? inqAdopterUid : otherUid,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 15),
                label: Text(
                  isChattingWithFoster ? 'Approve $displayAdopterName' : 'Approve Adopter',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),
      );
    }

    // 3. Approved, waiting for adopter to agree to terms
    if (status == 'approved' && !adopterAgreed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          border: Border(bottom: BorderSide(color: Colors.green.shade300)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
              child: const Icon(Icons.assignment_turned_in, size: 18, color: Color(0xFF2E7D32)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 2 of 4: Approved • Waiting for Adopter to Sign Terms',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                  ),
                  Text(
                    '$displayAdopterName is marked as the official adopter! They have been prompted to agree to Adoption Terms & Conditions in their app to generate the 5-character Adoption Pass.',
                    style: TextStyle(fontSize: 11.5, color: Colors.green.shade900),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32)),
                  ),
                  SizedBox(width: 6),
                  Text('Awaiting Terms Signature', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4. Terms Agreed & Adoption Pass Issued (Scheduled or Completed)
    if (adopterAgreed || status == 'scheduled' || status == 'completed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isHandoverCompleted ? const Color(0xFFF1F8E9) : const Color(0xFFE8F5E9),
          border: Border(bottom: BorderSide(color: isHandoverCompleted ? const Color(0xFFAED581) : const Color(0xFF81C784), width: 1.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isHandoverCompleted ? Icons.verified : Icons.qr_code_2_rounded,
                size: 22,
                color: const Color(0xFF1B5E20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isHandoverCompleted
                            ? 'Step 4 of 4: Adoption Completed • Handover Verified'
                            : 'Step 3 of 4: Terms Agreed • Adoption Pass Issued & Scheduled',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isHandoverCompleted ? Colors.green.shade100 : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isHandoverCompleted ? Colors.green.shade300 : Colors.blue.shade200),
                        ),
                        child: Text(
                          isHandoverCompleted ? 'COMPLETED' : 'SCHEDULED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: isHandoverCompleted ? Colors.green.shade900 : Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isHandoverCompleted
                        ? '$otherName has verified the pass and claimed $petName. The adoption is officially completed.'
                        : '$otherName signed all terms. Scheduled retrieval date: [${scheduledDate.isNotEmpty ? scheduledDate : 'At center'}].',
                    style: TextStyle(fontSize: 11.5, color: Colors.green.shade900),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // The 5-Character Adoption Pass Highlight Badge
            if (adoptionCode.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E7D32), width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ADOPTION PASS',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0xFF2E7D32)),
                        ),
                        SelectableText(
                          adoptionCode,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.0,
                            color: Color(0xFF1B5E20),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF2E7D32)),
                      tooltip: 'Copy Adoption Pass',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: adoptionCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied Adoption Pass: $adoptionCode'), duration: const Duration(seconds: 2)),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ],

            // Action Buttons: View Terms & Verify Handover
            TextButton.icon(
              onPressed: () => _showSignedTermsDialog(inquiryId, inquiryData),
              icon: const Icon(Icons.description_outlined, size: 15, color: Color(0xFF2E7D32)),
              label: const Text('View Terms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
              ),
            ),
            if (!isHandoverCompleted) ...[
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _showCenterHandoverDialog(inquiryId, inquiryData),
                icon: const Icon(Icons.verified, size: 16),
                label: const Text('Verify & Handover', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _handleApproveAdopter(
    String inquiryId,
    String petId,
    String petName,
    String adopterName,
    String adopterUid,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final db = FirebaseDatabase.instance.ref();

      // Enforce: Administrators manage shelter operations and cannot adopt pets
      final userSnap = await db.child('users').child(adopterUid).get();
      if (userSnap.exists && userSnap.value is Map) {
        final uMap = Map<String, dynamic>.from(userSnap.value as Map);
        final role = (uMap['role'] ?? '').toString().toLowerCase();
        final bool isTargetAdmin = uMap['isAdmin'] == true || role == 'admin';
        if (isTargetAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot approve: Administrators manage shelter operations and cannot adopt pets.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      await db.child('adoption_inquiries').child(inquiryId).update({
        'status': 'approved',
        'approvedAt': ServerValue.timestamp,
        'approvedBy': user.uid,
        'updatedAt': ServerValue.timestamp,
      });

      // Post chat announcement
      final text = "Foster / Admin marked $adopterName as the approved adopter for $petName! $adopterName can now click 'Agree to Terms & Conditions' to complete adoption and receive the 5-character Adoption Pass.";
      await db.child('chats').child(_selectedChatId!).child('messages').push().set({
        'senderUid': 'system',
        'senderName': 'Save-A-Paws',
        'text': text,
        'timestamp': ServerValue.timestamp,
      });

      await db.child('chats').child(_selectedChatId!).update({
        'lastMessage': text,
        'lastTimestamp': ServerValue.timestamp,
        'lastSenderUid': 'system',
      });

      // Notify adopter
      await db.child('system_messages').child(adopterUid).push().set({
        'title': 'Adoption Approved: $petName',
        'body': 'You have been marked as the approved adopter for $petName! Please review and agree to terms to get your 5-character Adoption Pass.',
        'timestamp': ServerValue.timestamp,
        'read': false,
        'type': 'adoption_approved',
        'petId': petId,
        'petName': petName,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked $adopterName as approved adopter for $petName.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving adopter: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showSignedTermsDialog(String inquiryId, Map<String, dynamic> data) {
    final petName = data['petName']?.toString() ?? 'Pet';
    final adopterName = data['adopterName']?.toString() ?? 'Adopter';
    final fosterName = data['fosterName']?.toString() ?? 'Foster';
    final adoptionCode = (data['adoptionCode']?.toString() ?? '').toUpperCase().trim();
    final scheduledDate = data['scheduledPickupDate']?.toString() ?? 'At Center';
    final num? termsAcceptedAt = data['termsAcceptedAt'] as num?;
    String signedDateStr = 'Verified';
    if (termsAcceptedAt != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(termsAcceptedAt.toInt());
      signedDateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.assignment_turned_in, color: Color(0xFF2E7D32), size: 22),
            const SizedBox(width: 8),
            Text('Signed Terms: $petName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF1F8E9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF81C784))),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_2, color: Color(0xFF1B5E20), size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('REGISTERED ADOPTION PASS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32), letterSpacing: 1.1)),
                          SelectableText(adoptionCode, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1B5E20), fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildTermsInfoRow('Adopter', adopterName),
              _buildTermsInfoRow('Foster / Shelter Staff', fosterName),
              _buildTermsInfoRow('Scheduled Retrieval Date', scheduledDate),
              _buildTermsInfoRow('Terms Signed At', signedDateStr),
              const Divider(height: 24),
              const Text(
                'Legal Undertaking & Care Commitments:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const Text(
                '• Lifelong humane care, adequate shelter, veterinary attention, and nutrition.\n'
                '• Strict no-resale and no-abandonment policy.\n'
                '• Handover verification required via 5-character pass at the center.',
                style: TextStyle(fontSize: 11.5, color: Colors.black87, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildTermsInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)))),
        ],
      ),
    );
  }

  Future<void> _showCenterHandoverDialog(String inquiryId, Map<String, dynamic> data) async {
    final petId = data['petId']?.toString() ?? '';
    final petName = data['petName']?.toString() ?? 'Rescued Pet';
    final adopterName = data['adopterName']?.toString() ?? 'Adopter';
    final expectedCode = (data['adoptionCode']?.toString() ?? '').toUpperCase().trim();

    final codeController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.verified, color: Color(0xFF2E7D32), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Center Handover Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verify the 5-character Adoption Pass presented by $adopterName at the center to complete the handover of $petName.',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8E9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF81C784)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'REGISTERED 5-CHARACTER ADOPTION PASS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32), letterSpacing: 1.1),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          expectedCode.isNotEmpty ? expectedCode : 'NO CODE',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1B5E20), fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 5,
                    decoration: InputDecoration(
                      labelText: 'Enter 5-character pass presented by adopter',
                      hintText: expectedCode,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      counterText: '',
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final input = codeController.text.trim().toUpperCase();
                        if (input.isNotEmpty && expectedCode.isNotEmpty && input != expectedCode) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid Adoption Pass code! Please recheck.'), backgroundColor: Colors.red),
                          );
                          return;
                        }

                        final messenger = ScaffoldMessenger.of(context);
                        setDialogState(() => isSubmitting = true);
                        try {
                          final db = FirebaseDatabase.instance.ref();
                          final updates = <String, dynamic>{
                            'adoption_inquiries/$inquiryId/petRetrieved': true,
                            'adoption_inquiries/$inquiryId/isHandedOver': true,
                            'adoption_inquiries/$inquiryId/status': 'completed',
                            'adoption_inquiries/$inquiryId/handoverCompletedAt': ServerValue.timestamp,
                            'adoption_inquiries/$inquiryId/updatedAt': ServerValue.timestamp,
                          };
                          if (petId.isNotEmpty && petId != 'general') {
                            updates['adoptionCenter/$petId/isAdopted'] = true;
                            updates['adoptionCenter/$petId/petRetrieved'] = true;
                            updates['adoptionCenter/$petId/status'] = 'adopted';
                          }
                          await db.update(updates);

                          // Post announcement in chat
                          await db.child('chats').child(_selectedChatId!).child('messages').push().set({
                            'senderUid': 'system',
                            'senderName': 'Save-A-Paws',
                            'text': '🎉 Adoption handover officially completed & verified! $petName is now officially home with $adopterName.',
                            'timestamp': ServerValue.timestamp,
                          });

                          await db.child('chats').child(_selectedChatId!).update({
                            'lastMessage': '🎉 Adoption handover completed & verified for $petName!',
                            'lastTimestamp': ServerValue.timestamp,
                            'lastSenderUid': 'system',
                          });

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Handover verified! $petName is officially adopted.'), backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Error completing handover: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (ctx.mounted) setDialogState(() => isSubmitting = false);
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm Handover & Complete', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}

