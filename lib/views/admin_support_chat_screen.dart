import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import 'admin_screen.dart';

class AdminSupportChatScreen extends StatefulWidget {
  final bool embeddedMode;

  const AdminSupportChatScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminSupportChatScreen> createState() => _AdminSupportChatScreenState();
}

class _AdminSupportChatScreenState extends State<AdminSupportChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();

  String? _selectedUserUid;
  String? _selectedChatId;
  Map<String, dynamic>? _selectedTicketData;

  bool _isSending = false;

  final List<String> _cannedReplies = [
    'Hello! How can I assist you today?',
    'Your verification request is approved!',
    'Please complete the adoption inquiry form in the app.',
    'Thank you for reporting this rescue emergency. Our team is on it!',
    'Is there anything else I can help you with?',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, $hour:$minute $ampm';
  }

  String _formatTimeOnly(dynamic timestamp) {
    if (timestamp == null) return '';
    int millis = 0;
    if (timestamp is num) millis = timestamp.toInt();
    if (millis == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $ampm';
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'adoption question':
        return const Color(0xFFE65100);
      case 'verification help':
        return const Color(0xFF00897B);
      case 'rescue & emergency':
        return Colors.red.shade700;
      case 'foster inquiries':
        return const Color(0xFF1E88E5);
      case 'donation & support':
        return const Color(0xFF6A1B9A);
      default:
        return Colors.blueGrey.shade700;
    }
  }

  Future<void> _acceptTicket(Map<String, dynamic> ticket) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final String userUid = ticket['uid']?.toString() ?? '';
    if (userUid.isEmpty) return;

    final String userName = ticket['userName']?.toString() ?? 'User';
    final String category = ticket['category']?.toString() ?? 'Inquiry';
    final String chatId = 'support_$userUid';

    String adminName = currentUser.displayName ?? '';
    if (adminName.isEmpty && currentUser.email != null) {
      adminName = currentUser.email!.split('@').first;
    }
    if (adminName.isEmpty) adminName = 'Admin';

    try {
      final db = FirebaseDatabase.instance.ref();

      // 1. Mark ticket active in queue using atomic transaction to prevent race conditions
      final queueRef = db.child('admin_support_queue').child(userUid);
      final txResult = await queueRef.runTransaction((mutableData) {
        if (mutableData == null) return Transaction.abort();
        if (mutableData is! Map) return Transaction.abort();
        final map = Map<String, dynamic>.from(mutableData);
        if (map['status'] != 'waiting') {
          return Transaction.abort();
        }
        map['status'] = 'active';
        map['assignedAdminUid'] = currentUser.uid;
        map['assignedAdminName'] = adminName;
        map['acceptedAt'] = ServerValue.timestamp;
        return Transaction.success(map);
      });

      if (!txResult.committed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This ticket was already claimed by another administrator.')),
          );
        }
        return;
      }

      // 2. Mark active in chat node
      await db.child('admin_support_chats').child(chatId).update({
        'status': 'active',
        'assignedAdminUid': currentUser.uid,
        'assignedAdminName': adminName,
      });

      // 3. Post automated greeting message into the chat
      final msgRef = db.child('admin_support_chats').child(chatId).child('messages').push();
      final msgKey = msgRef.key;

      await msgRef.set({
        'id': msgKey,
        'senderUid': currentUser.uid,
        'senderName': adminName,
        'text':
            'Hello $userName! I am $adminName from the SaveAPaws Admin Team. I have accepted your support ticket regarding "$category". How may I help you today?',
        'timestamp': ServerValue.timestamp,
        'isSystem': false,
        'isAdmin': true,
      });

      await db.child('admin_support_chats').child(chatId).update({
        'lastMessage': 'Admin $adminName joined the conversation.',
        'lastTimestamp': ServerValue.timestamp,
      });

      if (!mounted) return;
      setState(() {
        _selectedUserUid = userUid;
        _selectedChatId = chatId;
        _selectedTicketData = {
          ...ticket,
          'status': 'active',
          'assignedAdminUid': currentUser.uid,
          'assignedAdminName': adminName,
        };
        _tabController.animateTo(1); // Switch to active tab
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to $userName! Live chat session started.'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting ticket: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _closeTicket(Map<String, dynamic> ticket) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve & Close Support Ticket?'),
        content: Text(
          'This will close the live support session for ${ticket['userName'] ?? 'this user'}. The user will be notified that the ticket has been resolved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resolve & Close'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final userUid = ticket['uid']?.toString() ?? ticket['userUid']?.toString() ?? '';
    final chatId = ticket['chatId']?.toString() ?? 'support_$userUid';

    try {
      final db = FirebaseDatabase.instance.ref();

      // Post closing system message
      await db.child('admin_support_chats').child(chatId).child('messages').push().set({
        'senderUid': 'system',
        'senderName': 'System',
        'text': 'Support ticket has been marked as resolved and closed by Admin.',
        'timestamp': ServerValue.timestamp,
        'isSystem': true,
      });

      if (userUid.isNotEmpty) {
        await db.child('admin_support_queue').child(userUid).update({
          'status': 'closed',
          'closedAt': ServerValue.timestamp,
        });
      }

      await db.child('admin_support_chats').child(chatId).update({
        'status': 'closed',
        'closedAt': ServerValue.timestamp,
      });

      if (!mounted) return;
      setState(() {
        if (_selectedTicketData != null) {
          _selectedTicketData!['status'] = 'closed';
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Support ticket marked as resolved.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error closing ticket: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSending) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _selectedChatId == null) return;

    setState(() => _isSending = true);
    _replyController.clear();

    String adminName = currentUser.displayName ?? '';
    if (adminName.isEmpty && currentUser.email != null) {
      adminName = currentUser.email!.split('@').first;
    }
    if (adminName.isEmpty) adminName = 'Admin';

    try {
      final db = FirebaseDatabase.instance.ref();
      final msgRef = db.child('admin_support_chats').child(_selectedChatId!).child('messages').push();
      final msgKey = msgRef.key;

      await msgRef.set({
        'id': msgKey,
        'senderUid': currentUser.uid,
        'senderName': adminName,
        'text': text,
        'timestamp': ServerValue.timestamp,
        'isSystem': false,
        'isAdmin': true,
      });

      await db.child('admin_support_chats').child(_selectedChatId!).update({
        'lastMessage': text,
        'lastTimestamp': ServerValue.timestamp,
      });

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('admin_support_queue').onValue,
      builder: (context, queueSnap) {
        if (queueSnap.hasError) {
          final errorStr = queueSnap.error.toString().toLowerCase();
          if (errorStr.contains('permission-denied') || errorStr.contains('permission denied')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              AdminScreen.handlePermissionDenied(context);
            });
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
          }
          return Center(child: Text('Error loading queue: ${queueSnap.error}'));
        }

        final List<Map<String, dynamic>> queueTickets = [];
        final List<Map<String, dynamic>> activeTickets = [];
        final List<Map<String, dynamic>> resolvedTickets = [];

        if (queueSnap.hasData && queueSnap.data?.snapshot.value != null) {
          final raw = queueSnap.data!.snapshot.value;
          if (raw is Map) {
            raw.forEach((key, val) {
              if (val is Map) {
                final map = Map<String, dynamic>.from(val);
                map['uid'] = key.toString();
                final status = map['status']?.toString() ?? 'waiting';
                if (status == 'waiting') {
                  queueTickets.add(map);
                } else if (status == 'active') {
                  activeTickets.add(map);
                } else if (status == 'closed') {
                  resolvedTickets.add(map);
                }
              }
            });
          }
        }

        // Sort queue by joinedAt ascending (first come, first served)
        queueTickets.sort((a, b) {
          final int tA = (a['joinedAt'] is num) ? (a['joinedAt'] as num).toInt() : 0;
          final int tB = (b['joinedAt'] is num) ? (b['joinedAt'] as num).toInt() : 0;
          return tA.compareTo(tB);
        });

        // Sort active by acceptedAt or joinedAt descending
        activeTickets.sort((a, b) {
          final int tA = (a['acceptedAt'] is num) ? (a['acceptedAt'] as num).toInt() : 0;
          final int tB = (b['acceptedAt'] is num) ? (b['acceptedAt'] as num).toInt() : 0;
          return tB.compareTo(tA);
        });

        // Sort resolved by closedAt descending
        resolvedTickets.sort((a, b) {
          final int tA = (a['closedAt'] is num) ? (a['closedAt'] as num).toInt() : 0;
          final int tB = (b['closedAt'] is num) ? (b['closedAt'] as num).toInt() : 0;
          return tB.compareTo(tA);
        });

        return Container(
          color: const Color(0xFFF4F6F9),
          child: Column(
            children: [
              // Top KPI Banner
              _buildKpiBanner(
                waitingCount: queueTickets.length,
                activeCount: activeTickets.length,
                resolvedCount: resolvedTickets.length,
              ),

              // Main Workspace: Split Pane
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Queue & Chats List
                    SizedBox(
                      width: 380,
                      child: _buildLeftPanel(
                        queueTickets: queueTickets,
                        activeTickets: activeTickets,
                        resolvedTickets: resolvedTickets,
                      ),
                    ),

                    // Divider
                    Container(width: 1, color: Colors.grey.shade300),

                    // Right Column: Chat Room & Ticket Workspace
                    Expanded(
                      child: _buildRightPanel(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (widget.embeddedMode) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Support Chat & Queue'),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: content,
    );
  }

  // -------------------------------------------------------------
  // KPI Header Banner
  // -------------------------------------------------------------
  Widget _buildKpiBanner({
    required int waitingCount,
    required int activeCount,
    required int resolvedCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.support_agent_rounded, color: AppTheme.primaryOrange, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User Support Helpdesk & Queue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E2022)),
                  ),
                  Text(
                    'Real-time queue dispatch and live chat with mobile users',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),

          // Stats Pills
          _buildStatPill(
            icon: Icons.hourglass_top_rounded,
            label: 'Waiting in Queue',
            count: waitingCount,
            color: const Color(0xFFE65100),
            bgColor: const Color(0xFFFFF3E0),
          ),
          const SizedBox(width: 12),
          _buildStatPill(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Active Sessions',
            count: activeCount,
            color: const Color(0xFF00897B),
            bgColor: const Color(0xFFE0F2F1),
          ),
          const SizedBox(width: 12),
          _buildStatPill(
            icon: Icons.task_alt_rounded,
            label: 'Resolved',
            count: resolvedCount,
            color: Colors.blueGrey.shade700,
            bgColor: Colors.blueGrey.shade50,
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Left Panel: Queue & Session List
  // -------------------------------------------------------------
  Widget _buildLeftPanel({
    required List<Map<String, dynamic>> queueTickets,
    required List<Map<String, dynamic>> activeTickets,
    required List<Map<String, dynamic>> resolvedTickets,
  }) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Tab bar
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryOrange,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: AppTheme.primaryOrange,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Queue'),
                      if (queueTickets.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE65100),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${queueTickets.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Active'),
                      if (activeTickets.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00897B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${activeTickets.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Resolved'),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Queue list
                _buildQueueListView(queueTickets),

                // Tab 2: Active list
                _buildActiveListView(activeTickets),

                // Tab 3: Resolved list
                _buildResolvedListView(resolvedTickets),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueListView(List<Map<String, dynamic>> queueTickets) {
    if (queueTickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32), size: 36),
              ),
              const SizedBox(height: 14),
              const Text(
                'No Users in Queue',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2D3142)),
              ),
              const SizedBox(height: 6),
              Text(
                'All user support inquiries have been handled.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: queueTickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ticket = queueTickets[index];
        final spot = index + 1;
        final isSelected = _selectedUserUid == ticket['uid'];
        final category = ticket['category']?.toString() ?? 'Inquiry';
        final userName = ticket['userName']?.toString() ?? 'User';
        final question = ticket['question']?.toString() ?? '';
        final timeStr = _formatTimestamp(ticket['joinedAt']);

        return InkWell(
          onTap: () {
            setState(() {
              _selectedUserUid = ticket['uid'];
              _selectedChatId = 'support_${ticket['uid']}';
              _selectedTicketData = ticket;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFFFF8E1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top header: Spot #, Category & Time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: spot == 1 ? const Color(0xFFE65100) : Colors.grey.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SPOT #$spot',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        category,
                        style: TextStyle(
                          color: _getCategoryColor(category),
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // User Name
                Text(
                  userName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E2022)),
                ),
                const SizedBox(height: 4),

                // Question excerpt
                Text(
                  question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3),
                ),
                const SizedBox(height: 10),

                // Accept Button
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: () => _acceptTicket(ticket),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.support_agent_rounded, size: 16),
                    label: const Text(
                      'Accept Ticket & Chat',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveListView(List<Map<String, dynamic>> activeTickets) {
    if (activeTickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text('No Active Sessions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                'Accept a ticket from the queue to start a chat.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: activeTickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ticket = activeTickets[index];
        final isSelected = _selectedUserUid == ticket['uid'];
        final userName = ticket['userName']?.toString() ?? 'User';
        final category = ticket['category']?.toString() ?? 'Inquiry';
        final adminName = ticket['assignedAdminName']?.toString() ?? 'Admin';
        final timeStr = _formatTimestamp(ticket['acceptedAt'] ?? ticket['joinedAt']);

        return InkWell(
          onTap: () {
            setState(() {
              _selectedUserUid = ticket['uid'];
              _selectedChatId = 'support_${ticket['uid']}';
              _selectedTicketData = ticket;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE0F2F1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFF00897B) : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF00897B).withValues(alpha: 0.15),
                      radius: 20,
                      child: const Icon(Icons.person, color: Color(0xFF00897B), size: 22),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              userName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(timeStr, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        category,
                        style: TextStyle(
                          color: _getCategoryColor(category),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Assigned: $adminName',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResolvedListView(List<Map<String, dynamic>> resolvedTickets) {
    if (resolvedTickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text('No resolved tickets yet.', style: TextStyle(color: Colors.grey.shade500)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: resolvedTickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ticket = resolvedTickets[index];
        final isSelected = _selectedUserUid == ticket['uid'];
        final userName = ticket['userName']?.toString() ?? 'User';
        final category = ticket['category']?.toString() ?? 'Inquiry';
        final timeStr = _formatTimestamp(ticket['closedAt'] ?? ticket['joinedAt']);

        return InkWell(
          onTap: () {
            setState(() {
              _selectedUserUid = ticket['uid'];
              _selectedChatId = 'support_${ticket['uid']}';
              _selectedTicketData = ticket;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.grey.shade100 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(category, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Text(timeStr, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // Right Panel: Chat Room & Ticket Action Center
  // -------------------------------------------------------------
  Widget _buildRightPanel() {
    if (_selectedTicketData == null || _selectedChatId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.question_answer_outlined, color: AppTheme.primaryOrange, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Support Ticket Selected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a ticket from the queue or active list on the left to start assisting users.',
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final ticket = _selectedTicketData!;
    final status = ticket['status']?.toString() ?? 'waiting';
    final userName = ticket['userName']?.toString() ?? 'User';
    final userEmail = ticket['userEmail']?.toString() ?? '';
    final category = ticket['category']?.toString() ?? 'General Inquiry';
    final question = ticket['question']?.toString() ?? '';

    // If waiting, show ticket review and large "Accept" CTA
    if (status == 'waiting') {
      return Container(
        padding: const EdgeInsets.all(32),
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFFE65100)),
                  SizedBox(width: 8),
                  Text(
                    'Ticket In Queue (Waiting for Admin)',
                    style: TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // User Info
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primaryOrange.withValues(alpha: 0.15),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: AppTheme.primaryOrange, fontWeight: FontWeight.bold, fontSize: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (userEmail.isNotEmpty)
                        Text(
                          userEmail,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Category tag
            Text(
              'TOPIC / CATEGORY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getCategoryColor(category).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: _getCategoryColor(category),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Question
            Text(
              'USER QUESTION / INQUIRY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                question.isNotEmpty ? question : '(No description provided)',
                style: const TextStyle(fontSize: 15, height: 1.4, color: Color(0xFF1E2022)),
              ),
            ),
            const SizedBox(height: 36),

            // Accept CTA
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _acceptTicket(ticket),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.support_agent_rounded, size: 20),
                label: const Text(
                  'Accept Ticket & Open Live Chat',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Active or Closed Chat View
    return Container(
      color: const Color(0xFFF9FAFC),
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: status == 'active'
                      ? const Color(0xFF00897B).withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                  child: Icon(
                    Icons.person,
                    color: status == 'active' ? const Color(0xFF00897B) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: status == 'active'
                                  ? const Color(0xFFE0F2F1)
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status == 'active' ? 'LIVE SESSION' : 'CLOSED',
                              style: TextStyle(
                                color: status == 'active'
                                    ? const Color(0xFF00897B)
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Category: $category • ${userEmail.isNotEmpty ? userEmail : "User"}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),

                if (status == 'active')
                  ElevatedButton.icon(
                    onPressed: () => _closeTicket(ticket),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Resolve & Close Ticket', style: TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
          ),

          // Message Transcript Stream
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref()
                  .child('admin_support_chats')
                  .child(_selectedChatId!)
                  .child('messages')
                  .orderByChild('timestamp')
                  .onValue,
              builder: (context, msgSnap) {
                if (!msgSnap.hasData || msgSnap.data?.snapshot.value == null) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
                }

                final raw = msgSnap.data!.snapshot.value;
                final List<Map<String, dynamic>> messages = [];

                if (raw is Map) {
                  raw.forEach((key, val) {
                    if (val is Map) {
                      messages.add(Map<String, dynamic>.from(val));
                    }
                  });
                }

                messages.sort((a, b) {
                  final int tA = (a['timestamp'] is num) ? (a['timestamp'] as num).toInt() : 0;
                  final int tB = (b['timestamp'] is num) ? (b['timestamp'] as num).toInt() : 0;
                  return tA.compareTo(tB);
                });

                // Auto-scroll
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _messagesScrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isAdmin = msg['isAdmin'] == true;
                    final isSystem = msg['isSystem'] == true;
                    final text = msg['text']?.toString() ?? '';
                    final senderName = msg['senderName']?.toString() ?? 'User';
                    final timeStr = _formatTimeOnly(msg['timestamp']);

                    if (isSystem) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              text,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment:
                            isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isAdmin) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.grey.shade300,
                              child: const Icon(Icons.person, size: 14, color: Colors.black54),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 500),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isAdmin ? const Color(0xFF00897B) : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(isAdmin ? 14 : 2),
                                  bottomRight: Radius.circular(isAdmin ? 2 : 14),
                                ),
                                border: isAdmin ? null : Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAdmin ? 'Admin ($senderName)' : senderName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isAdmin ? Colors.white70 : AppTheme.primaryOrange,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    text,
                                    style: TextStyle(
                                      color: isAdmin ? Colors.white : const Color(0xFF1E2022),
                                      fontSize: 14,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isAdmin ? Colors.white60 : Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isAdmin) const SizedBox(width: 4),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Canned Quick Reply Chips (Only if active)
          if (status == 'active') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _cannedReplies.map((reply) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(reply, style: const TextStyle(fontSize: 12)),
                        backgroundColor: const Color(0xFFF1F3F5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onPressed: () {
                          _replyController.text = reply;
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Message Composer Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6F8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: TextField(
                        controller: _replyController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Type your message to user (Press Enter or Send)...',
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 13.5),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: const Text(
                'This ticket has been resolved and closed.',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
