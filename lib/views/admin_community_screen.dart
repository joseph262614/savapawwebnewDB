import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/platform_picker.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';

class AdminCommunityScreen extends StatefulWidget {
  final bool embeddedMode;
  const AdminCommunityScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminCommunityScreen> createState() => _AdminCommunityScreenState();
}

class _AdminCommunityScreenState extends State<AdminCommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final NotificationService _notificationService = NotificationService();

  List<Map<String, dynamic>> _posts = [];
  bool _isLoadingPosts = true;
  String _postsSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _notificationService.init();
    _listenToPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(int timestamp) {
    if (timestamp <= 0) return 'Just now';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$month ${dt.day}, ${dt.year} • $hour:$min $ampm';
  }

  void _listenToPosts() {
    _db.child('posts').onValue.listen((event) {
      if (!mounted) return;
      final snapshot = event.snapshot;
      List<Map<String, dynamic>> fetched = [];

      if (snapshot.exists && snapshot.value != null) {
        final dynamic raw = snapshot.value;
        if (raw is Map) {
          raw.forEach((key, value) {
            if (value is Map) {
              final item = Map<String, dynamic>.from(value);
              item['id'] = key.toString();
              fetched.add(item);
            }
          });
        }
      }

      fetched.sort((a, b) {
        final tA = a['timestamp'] is int ? a['timestamp'] as int : 0;
        final tB = b['timestamp'] is int ? b['timestamp'] as int : 0;
        return tB.compareTo(tA);
      });

      setState(() {
        _posts = fetched;
        _isLoadingPosts = false;
      });
    }, onError: (err) {
      if (mounted) setState(() => _isLoadingPosts = false);
    });
  }

  Future<void> _openCreateAnnouncementDialog() async {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    final imageController = TextEditingController();
    String? base64Image;
    String selectedCategory = 'General Notice';
    String selectedPriority = 'normal';
    bool isBroadcasting = false;

    final categories = [
      'General Notice',
      'Adoption Fair',
      'Urgent Rescue',
      'Lost & Found Alert',
      'Health & Vaccination',
      'System Update',
    ];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.campaign, color: AppTheme.primaryOrange, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text('Broadcast Announcement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: 550,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This announcement will be sent to all users inside the app and will trigger a system desktop/mobile notification outside the app.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // Title
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'Announcement Title *',
                          hintText: 'e.g. Mega Adoption Fair this Saturday!',
                          prefixIcon: const Icon(Icons.title, color: AppTheme.primaryOrange),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Category & Priority Row
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: selectedCategory,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: categories.map((cat) {
                                return DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setDialogState(() => selectedCategory = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: selectedPriority,
                              decoration: InputDecoration(
                                labelText: 'Priority',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'normal', child: Text('🟢 Normal Priority', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'high', child: Text('🟠 High Priority', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'urgent', child: Text('🔴 Urgent Alert', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (val) {
                                if (val != null) setDialogState(() => selectedPriority = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Message Body
                      TextField(
                        controller: messageController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Message Body *',
                          hintText: 'Provide full details for the community announcement...',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Photo Upload Picker
                      InkWell(
                        onTap: () async {
                          try {
                            if (kIsWeb) {
                              final webImg = await pickImageWeb();
                              if (webImg != null && webImg.bytes.isNotEmpty) {
                                final base64String = "data:image/jpeg;base64,${base64Encode(webImg.bytes)}";
                                setDialogState(() {
                                  base64Image = base64String;
                                });
                                return;
                              }
                            }

                            final picker = ImagePicker();
                            final img = await picker.pickImage(source: ImageSource.gallery);
                            if (img != null) {
                              final bytes = await img.readAsBytes();
                              setDialogState(() {
                                base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
                              });
                            }
                          } catch (e) {
                            debugPrint("Image picker error: $e");
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          height: (base64Image != null || imageController.text.trim().isNotEmpty) ? 140 : 64,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: (base64Image != null || imageController.text.trim().isNotEmpty)
                              ? Stack(
                                  children: [
                                    Center(
                                      child: _buildImageWidget(base64Image ?? imageController.text.trim()),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: Colors.black54,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.close, color: Colors.white, size: 14),
                                          onPressed: () => setDialogState(() {
                                            base64Image = null;
                                            imageController.clear();
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primaryOrange, size: 24),
                                    const SizedBox(width: 8),
                                    Text('Upload Photo / Banner', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Optional Image URL
                      TextField(
                        controller: imageController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Or Banner Image URL (Optional)',
                          hintText: 'https://example.com/banner.jpg',
                          prefixIcon: const Icon(Icons.image_outlined, color: Colors.grey),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isBroadcasting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isBroadcasting
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          final body = messageController.text.trim();

                          if (title.isEmpty || body.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please fill in both title and message body.'), backgroundColor: Colors.red),
                            );
                            return;
                          }

                          setDialogState(() => isBroadcasting = true);

                          final currentUser = FirebaseAuth.instance.currentUser;
                          final authorName = currentUser?.displayName ?? 'SaveAPaws Admin';
                          final authorUid = currentUser?.uid ?? 'admin';
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);

                          try {
                            final effectiveImg = base64Image ?? (imageController.text.trim().isEmpty ? null : imageController.text.trim());
                            await _notificationService.broadcastAnnouncement(
                              title: title,
                              message: body,
                              category: selectedCategory,
                              priority: selectedPriority,
                              authorUid: authorUid,
                              authorName: authorName,
                              imageUrl: effectiveImg,
                            );

                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('📢 Announcement successfully broadcasted!'),
                                backgroundColor: Color(0xFF2E7D32),
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isBroadcasting = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Error broadcasting: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  icon: isBroadcasting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(isBroadcasting ? 'Broadcasting...' : 'Broadcast Now'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openCreatePostDialog() async {
    final captionController = TextEditingController();
    final locationController = TextEditingController(text: 'SaveAPaws Community Hub, Manila');
    final imageUrlController = TextEditingController();
    String? base64Image;
    bool isOfficialAdmin = true;
    bool isPublishing = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.post_add, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text('Create Official Community Post', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: 550,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Publish an official update directly into the user community feed.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // Caption
                      TextField(
                        controller: captionController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Caption / Story *',
                          hintText: 'Share a story, rescue update, or shelter event...',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Location
                      TextField(
                        controller: locationController,
                        decoration: InputDecoration(
                          labelText: 'Location',
                          prefixIcon: const Icon(Icons.location_on_outlined, color: AppTheme.primaryOrange),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Photo Upload Picker
                      InkWell(
                        onTap: () async {
                          try {
                            if (kIsWeb) {
                              final webImg = await pickImageWeb();
                              if (webImg != null && webImg.bytes.isNotEmpty) {
                                final base64String = "data:image/jpeg;base64,${base64Encode(webImg.bytes)}";
                                setDialogState(() {
                                  base64Image = base64String;
                                });
                                return;
                              }
                            }

                            final picker = ImagePicker();
                            final img = await picker.pickImage(source: ImageSource.gallery);
                            if (img != null) {
                              final bytes = await img.readAsBytes();
                              setDialogState(() {
                                base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
                              });
                            }
                          } catch (e) {
                            debugPrint("Image picker error: $e");
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          height: (base64Image != null || imageUrlController.text.trim().isNotEmpty) ? 140 : 64,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: (base64Image != null || imageUrlController.text.trim().isNotEmpty)
                              ? Stack(
                                  children: [
                                    Center(
                                      child: _buildImageWidget(base64Image ?? imageUrlController.text.trim()),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: Colors.black54,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.close, color: Colors.white, size: 14),
                                          onPressed: () => setDialogState(() {
                                            base64Image = null;
                                            imageUrlController.clear();
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add_photo_alternate_outlined, color: Colors.blue, size: 24),
                                    const SizedBox(width: 8),
                                    Text('Upload Post Photo', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Optional Image URL
                      TextField(
                        controller: imageUrlController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Or Photo / Image URL (Optional)',
                          hintText: 'https://images.unsplash.com/...',
                          prefixIcon: const Icon(Icons.photo_outlined, color: Colors.grey),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Official Badge switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Badge as Official Admin Post', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        subtitle: const Text('Adds verified "SaveAPaws Team" badge in the feed', style: TextStyle(fontSize: 11.5)),
                        value: isOfficialAdmin,
                        activeThumbColor: AppTheme.primaryOrange,
                        onChanged: (val) => setDialogState(() => isOfficialAdmin = val),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isPublishing ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isPublishing
                      ? null
                      : () async {
                          final caption = captionController.text.trim();
                          if (caption.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a caption for the post.'), backgroundColor: Colors.red),
                            );
                            return;
                          }

                          setDialogState(() => isPublishing = true);

                          final currentUser = FirebaseAuth.instance.currentUser;
                          final authorName = currentUser?.displayName ?? 'SaveAPaws Admin';
                          final authorUid = currentUser?.uid ?? 'admin';
                          final effectiveImageUrl = base64Image ?? imageUrlController.text.trim();
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);

                          try {
                            final newPostRef = _db.child('posts').push();
                            await newPostRef.set({
                              'userId': authorUid,
                              'username': authorName,
                              'userAvatar': currentUser?.photoURL ?? '',
                              'location': locationController.text.trim().isEmpty
                                  ? 'SaveAPaws Shelter'
                                  : locationController.text.trim(),
                              'imageUrls': effectiveImageUrl.isNotEmpty ? [effectiveImageUrl] : [],
                              'description': caption,
                              'timestamp': ServerValue.timestamp,
                              'commentsCount': 0,
                              'isAdminPost': isOfficialAdmin,
                            });

                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Post published to Community Feed!'),
                                backgroundColor: Color(0xFF2E7D32),
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isPublishing = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to publish post: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  icon: isPublishing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 18),
                  label: Text(isPublishing ? 'Publishing...' : 'Publish Post'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteAnnouncement(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: Text('Are you sure you want to remove "$title"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _notificationService.deleteAnnouncement(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement removed.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _confirmDeletePost(String id, String author) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Community Post'),
        content: Text('Are you sure you want to delete this post by $author?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.child('posts').child(id).remove();
      await _db.child('comments').child(id).remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted from feed.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildImageWidget(String? url) {
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    Widget imageContent;
    if (url.startsWith('data:image')) {
      try {
        final commaIdx = url.indexOf(',');
        final base64Str = commaIdx != -1 ? url.substring(commaIdx + 1) : url;
        final cleanBase64 = base64Str.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '').trim();
        final bytes = base64Decode(cleanBase64);
        imageContent = Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, error, __) {
            debugPrint("Image.memory error: $error");
            return const Center(child: Icon(Icons.broken_image, color: Colors.grey));
          },
        );
      } catch (e) {
        debugPrint("base64Decode error in _buildImageWidget: $e");
        return const SizedBox.shrink();
      }
    } else {
      imageContent = Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, error, __) {
          debugPrint("Image.network error: $error");
          return const Center(child: Icon(Icons.broken_image, color: Colors.grey));
        },
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: imageContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _notificationService,
      builder: (context, _) {
        final announcements = _notificationService.announcements;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: widget.embeddedMode
              ? null
              : AppBar(
                  title: const Text('Community & Announcements', style: TextStyle(fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header with Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Community & Announcements Hub',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Broadcast official notices (notifies inside & outside the app) and manage community posts.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        final isAnnouncementsTab = _tabController.index == 0;
                        return ElevatedButton.icon(
                          key: ValueKey<bool>(isAnnouncementsTab),
                          onPressed: isAnnouncementsTab
                              ? _openCreateAnnouncementDialog
                              : _openCreatePostDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isAnnouncementsTab
                                ? AppTheme.primaryOrange
                                : const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            elevation: 1,
                          ),
                          icon: Icon(
                            isAnnouncementsTab ? Icons.campaign : Icons.post_add,
                            size: 20,
                          ),
                          label: Text(
                            isAnnouncementsTab ? 'Broadcast Announcement' : 'New Admin Post',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // KPI Counter Cards
                Row(
                  children: [
                    _buildKpiCard(
                      title: 'Announcements Broadcasted',
                      count: announcements.length.toString(),
                      icon: Icons.campaign,
                      color: AppTheme.primaryOrange,
                    ),
                    const SizedBox(width: 16),
                    _buildKpiCard(
                      title: 'Active Community Posts',
                      count: _posts.length.toString(),
                      icon: Icons.forum_rounded,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 16),
                    _buildKpiCard(
                      title: 'Urgent Alerts',
                      count: announcements.where((a) => a['priority'] == 'urgent').length.toString(),
                      icon: Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Tab Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.primaryOrange,
                    labelColor: AppTheme.primaryOrange,
                    unselectedLabelColor: Colors.grey.shade600,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.campaign_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text('Announcements (${announcements.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.dynamic_feed_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text('Community Feed (${_posts.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Announcements View
                      _buildAnnouncementsTab(announcements),

                      // Community Feed View
                      _buildCommunityFeedTab(),
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

  Widget _buildKpiCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    title,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementsTab(List<Map<String, dynamic>> announcements) {
    if (announcements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No announcements broadcasted yet.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Click "Broadcast Announcement" to notify users inside and outside the app.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: announcements.length,
      itemBuilder: (context, index) {
        final a = announcements[index];
        final id = a['id']?.toString() ?? '';
        final title = a['title']?.toString() ?? 'Announcement';
        final message = a['message']?.toString() ?? '';
        final category = a['category']?.toString() ?? 'Notice';
        final priority = a['priority']?.toString().toLowerCase() ?? 'normal';
        final author = a['authorName']?.toString() ?? 'Admin';
        final imageUrl = a['imageUrl']?.toString();
        final ts = a['timestamp'] is int ? a['timestamp'] as int : 0;
        final dateStr = _formatDate(ts);

        Color priorityColor = Colors.green;
        if (priority == 'urgent') priorityColor = Colors.redAccent;
        if (priority == 'high') priorityColor = AppTheme.primaryOrange;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: priorityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            priority.toUpperCase(),
                            style: TextStyle(color: priorityColor, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      tooltip: 'Delete Announcement',
                      onPressed: () => _confirmDeleteAnnouncement(id, title),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(message, style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800, height: 1.4)),
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildImageWidget(imageUrl),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Broadcast by $author', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                    Text(dateStr, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommunityFeedTab() {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
    }

    final filtered = _posts.where((p) {
      if (_postsSearchQuery.isEmpty) return true;
      final desc = p['description']?.toString().toLowerCase() ?? '';
      final author = p['username']?.toString().toLowerCase() ?? '';
      final loc = p['location']?.toString().toLowerCase() ?? '';
      final q = _postsSearchQuery.toLowerCase();
      return desc.contains(q) || author.contains(q) || loc.contains(q);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No posts found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Create an official post or wait for users to share moments.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            onChanged: (val) => setState(() => _postsSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search posts by author, description, or location...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
            ),
          ),
        ),

        // Posts List
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final post = filtered[index];
              final id = post['id']?.toString() ?? '';
              final author = post['username']?.toString() ?? 'Community User';
              final authorAvatar = post['userAvatar']?.toString() ?? '';
              final location = post['location']?.toString() ?? 'Philippines';
              final desc = post['description']?.toString() ?? '';
              final isAdminPost = post['isAdminPost'] == true;
              final commentsCount = post['commentsCount'] ?? 0;
              final ts = post['timestamp'] is int ? post['timestamp'] as int : 0;
              final dateStr = _formatDate(ts);

              List<String> imageUrls = [];
              if (post['imageUrls'] is List) {
                imageUrls = (post['imageUrls'] as List).map((e) => e.toString()).toList();
              }

              int likesCount = 0;
              if (post['likes'] is Map) {
                likesCount = (post['likes'] as Map).length;
              }

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.primaryOrange.withValues(alpha: 0.15),
                            backgroundImage: authorAvatar.isNotEmpty ? NetworkImage(authorAvatar) : null,
                            child: authorAvatar.isEmpty ? const Icon(Icons.person, color: AppTheme.primaryOrange) : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        author,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isAdminPost) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryOrange,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'OFFICIAL ADMIN',
                                          style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  '$location • $dateStr',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            tooltip: 'Delete Post',
                            onPressed: () => _confirmDeletePost(id, author),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Caption
                      Text(desc, style: const TextStyle(fontSize: 13.5, height: 1.4)),

                      // Image(s)
                      if (imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildImageWidget(imageUrls.first),
                      ],
                      const SizedBox(height: 12),

                      // Engagement stats
                      Row(
                        children: [
                          const Icon(Icons.favorite, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 4),
                          Text('$likesCount likes', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(width: 16),
                          const Icon(Icons.comment_outlined, color: Colors.grey, size: 16),
                          const SizedBox(width: 4),
                          Text('$commentsCount comments', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
  }
}
