import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/app_optimized_image.dart';
import 'admin_screen.dart';

class AdminReportedPostsScreen extends StatefulWidget {
  final bool embeddedMode;

  const AdminReportedPostsScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminReportedPostsScreen> createState() => _AdminReportedPostsScreenState();
}

class _AdminReportedPostsScreenState extends State<AdminReportedPostsScreen> {
  String _selectedFilter = 'pending'; // 'all', 'pending', 'resolved', 'dismissed'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder(
      stream: FirebaseDatabase.instance.ref().child('reported_posts').onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryOrange),
          );
        }

        if (snapshot.hasError) {
          final errorStr = snapshot.error.toString().toLowerCase();
          if (errorStr.contains('permission-denied') || errorStr.contains('permission denied')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              AdminScreen.handlePermissionDenied(context);
            });
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('Failed to load reports: ${snapshot.error}', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }

        final dynamic rawData = snapshot.data?.snapshot.value;
        Map<dynamic, dynamic> reportsMap = {};
        if (rawData is Map) {
          reportsMap = rawData;
        }

        List<Map<String, dynamic>> allReports = [];
        reportsMap.forEach((key, value) {
          if (value is Map) {
            final report = Map<String, dynamic>.from(value);
            report['reportKey'] = key.toString();
            allReports.add(report);
          }
        });

        // Newest first
        allReports.sort((a, b) {
          final tA = a['timestamp'] is num ? (a['timestamp'] as num).toInt() : 0;
          final tB = b['timestamp'] is num ? (b['timestamp'] as num).toInt() : 0;
          return tB.compareTo(tA);
        });

        final pendingCount = allReports.where((r) => (r['status'] ?? 'pending') == 'pending').length;
        final resolvedCount = allReports.where((r) => r['status'] == 'resolved').length;
        final dismissedCount = allReports.where((r) => r['status'] == 'dismissed').length;

        // Filter by status
        List<Map<String, dynamic>> filtered = allReports;
        if (_selectedFilter != 'all') {
          filtered = filtered.where((r) => (r['status'] ?? 'pending') == _selectedFilter).toList();
        }

        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filtered = filtered.where((r) {
            final reason = (r['reason'] ?? '').toString().toLowerCase();
            final details = (r['details'] ?? '').toString().toLowerCase();
            final author = (r['postAuthorUsername'] ?? '').toString().toLowerCase();
            final reporter = (r['reportedByUsername'] ?? '').toString().toLowerCase();
            final desc = (r['postDescription'] ?? '').toString().toLowerCase();
            return reason.contains(q) || details.contains(q) || author.contains(q) || reporter.contains(q) || desc.contains(q);
          }).toList();
        }

        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktop = screenWidth > 900;

        return Column(
          children: [
            _buildTopBar(
              totalCount: allReports.length,
              pendingCount: pendingCount,
              resolvedCount: resolvedCount,
              dismissedCount: dismissedCount,
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState()
                  : (isDesktop
                      ? _buildDesktopList(filtered)
                      : _buildMobileList(filtered)),
            ),
          ],
        );
      },
    );

    if (widget.embeddedMode) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reported Community Posts'),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _buildTopBar({
    required int totalCount,
    required int pendingCount,
    required int resolvedCount,
    required int dismissedCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search by author, reporter, reason, or content...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'All ($totalCount)'),
                const SizedBox(width: 8),
                _buildFilterChip('pending', 'Pending ($pendingCount)', badgeColor: Colors.orange),
                const SizedBox(width: 8),
                _buildFilterChip('resolved', 'Resolved ($resolvedCount)', badgeColor: Colors.green),
                const SizedBox(width: 8),
                _buildFilterChip('dismissed', 'Dismissed ($dismissedCount)', badgeColor: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, {Color? badgeColor}) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No reports match your search' : 'No reports found',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilter == 'pending' ? 'All reported posts have been moderated!' : 'No records under this filter.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopList(List<Map<String, dynamic>> reports) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SizedBox(width: 80, child: Text('Thumbnail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))),
                Expanded(flex: 3, child: Text('Report Reason / Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))),
                Expanded(flex: 2, child: Text('Post Author', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))),
                Expanded(flex: 2, child: Text('Reported By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))),
                SizedBox(width: 100, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))),
                SizedBox(width: 160, child: Text('Actions', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return _buildDesktopTableRow(report);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTableRow(Map<String, dynamic> report) {
    final String reportKey = report['reportKey'] ?? '';
    final String postId = report['postId'] ?? '';
    final String reason = report['reason'] ?? 'No reason provided';
    final String details = report['details'] ?? '';
    final String postAuthor = report['postAuthorUsername'] ?? 'User';
    final String reportedBy = report['reportedByUsername'] ?? 'Anonymous';
    final String postImageUrl = report['postImageUrl'] ?? '';
    final String status = report['status'] ?? 'pending';

    DateTime reportDate = DateTime.now();
    if (report['timestamp'] is num) {
      reportDate = DateTime.fromMillisecondsSinceEpoch((report['timestamp'] as num).toInt());
    }

    Color badgeColor = Colors.red;
    if (status == 'resolved') badgeColor = Colors.green;
    if (status == 'dismissed') badgeColor = Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Thumbnail
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 50,
                child: _buildImageThumbnail(postImageUrl),
              ),
            ),
          ),
          // Reason & Details
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Note: $details',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Author
          Expanded(
            flex: 2,
            child: Text(
              '@$postAuthor',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Reported By & Date
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@$reportedBy',
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDate(reportDate),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          // Status badge
          SizedBox(
            width: 100,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ),
          ),
          // Actions
          SizedBox(
            width: 160,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'View Details & Moderate',
                  icon: const Icon(Icons.visibility_outlined, size: 20, color: AppTheme.primaryOrange),
                  onPressed: () => _showReviewDialog(report),
                ),
                if (status == 'pending') ...[
                  IconButton(
                    tooltip: 'Dismiss Report',
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () => _updateReportStatus(reportKey, 'dismissed'),
                  ),
                  IconButton(
                    tooltip: 'Delete Post',
                    icon: const Icon(Icons.delete_forever, size: 20, color: Colors.red),
                    onPressed: () => _confirmDeletePost(reportKey, postId),
                  ),
                ] else ...[
                  IconButton(
                    tooltip: 'Delete Log',
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    onPressed: () => _deleteReportLog(reportKey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(List<Map<String, dynamic>> reports) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        final String reportKey = report['reportKey'] ?? '';
        final String postId = report['postId'] ?? '';
        final String reason = report['reason'] ?? 'No reason provided';
        final String details = report['details'] ?? '';
        final String status = report['status'] ?? 'pending';
        final String postAuthor = report['postAuthorUsername'] ?? 'User';

        Color badgeColor = Colors.red;
        if (status == 'resolved') badgeColor = Colors.green;
        if (status == 'dismissed') badgeColor = Colors.grey;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Note: $details', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 8),
                Text('Author: @$postAuthor', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _showReviewDialog(report),
                      child: const Text('Review Post'),
                    ),
                    if (status == 'pending') ...[
                      TextButton(
                        onPressed: () => _updateReportStatus(reportKey, 'dismissed'),
                        child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
                      ),
                      TextButton(
                        onPressed: () => _confirmDeletePost(reportKey, postId),
                        child: const Text('Delete Post', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageThumbnail(String imageUrl) {
    return AppOptimizedImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      cacheWidth: 160,
      cacheHeight: 160,
      errorWidget: Container(color: Colors.grey.shade200, child: const Icon(Icons.article_outlined, size: 24, color: Colors.grey)),
    );
  }

  void _showReviewDialog(Map<String, dynamic> report) {
    final String reportKey = report['reportKey'] ?? '';
    final String postId = report['postId'] ?? '';
    final String reason = report['reason'] ?? 'No reason provided';
    final String details = report['details'] ?? '';
    final String reportedBy = report['reportedByUsername'] ?? 'Anonymous';
    final String reportedByEmail = report['reportedByEmail'] ?? '';
    final String postAuthor = report['postAuthorUsername'] ?? 'User';
    final String postDescription = report['postDescription'] ?? '';
    final String postImageUrl = report['postImageUrl'] ?? '';
    final String status = report['status'] ?? 'pending';

    DateTime reportDate = DateTime.now();
    if (report['timestamp'] is num) {
      reportDate = DateTime.fromMillisecondsSinceEpoch((report['timestamp'] as num).toInt());
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 700,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Report Violation: $reason',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Reporter Note Callout
                if (details.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Description provided by Reporter:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown),
                        ),
                        const SizedBox(height: 4),
                        Text(details, style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Metadata row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Reported By', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('@$reportedBy', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            if (reportedByEmail.isNotEmpty)
                              Text(reportedByEmail, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(height: 2),
                            Text(_formatDate(reportDate), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Post Author', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('@$postAuthor', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text('Status: ${status.toUpperCase()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Post Content Preview
                const Text('Reported Post Content:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),

                if (postDescription.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(postDescription, style: const TextStyle(fontSize: 14)),
                  ),

                if (postImageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 240,
                      child: _buildImageThumbnail(postImageUrl),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == 'pending') ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Dismiss Report'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _updateReportStatus(reportKey, 'dismissed');
                        },
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete_forever, size: 16, color: Colors.white),
                        label: const Text('Delete Offending Post', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDeletePost(reportKey, postId);
                        },
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: const Text('Delete Report Log', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteReportLog(reportKey);
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateReportStatus(String reportKey, String newStatus) async {
    try {
      await FirebaseDatabase.instance.ref().child('reported_posts').child(reportKey).update({
        'status': newStatus,
        'reviewedAt': ServerValue.timestamp,
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report marked as $newStatus.'), backgroundColor: Colors.black87),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDeletePost(String reportKey, String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reported Post?'),
        content: const Text(
          'This will permanently delete the post and its comments from the community feed and mark the report as resolved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Post', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (postId.isNotEmpty) {
        await FirebaseDatabase.instance.ref().child('posts').child(postId).remove();
        await FirebaseDatabase.instance.ref().child('comments').child(postId).remove();
      }

      await FirebaseDatabase.instance.ref().child('reported_posts').child(reportKey).update({
        'status': 'resolved',
        'actionTaken': 'deleted_post',
        'reviewedAt': ServerValue.timestamp,
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted and report marked as resolved.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting post: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteReportLog(String reportKey) async {
    try {
      await FirebaseDatabase.instance.ref().child('reported_posts').child(reportKey).remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report log removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
