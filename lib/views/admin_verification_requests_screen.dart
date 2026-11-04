import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../theme/app_theme.dart';

import 'admin_screen.dart';

class AdminVerificationRequestsScreen extends StatelessWidget {
  /// When true, renders without its own Scaffold/AppBar (embedded in AdminScreen sidebar layout).
  /// When false, renders as a standalone page with AppBar (mobile layout).
  final bool embeddedMode;

  const AdminVerificationRequestsScreen({super.key, this.embeddedMode = false});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // DEBUG: Prints your current status to help solve the Permission Denied error
    debugPrint("--- ADMIN ACCESS DEBUG ---");
    debugPrint("Logged in as: ${user?.email}");
    debugPrint("Current UID: ${user?.uid}");
    debugPrint("--------------------------");

    final body = StreamBuilder(
      stream: FirebaseDatabase.instance.ref().child('verificationRequests').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("DATABASE ERROR: ${snapshot.error}");
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
                  const SizedBox(height: 16),
                  Text('Access Denied', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('UID: ${user?.uid}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  const Text(
                    'Please verify that this account has role: "admin" in your database.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return _buildEmptyState();
        }

        final dynamic rawData = snapshot.data!.snapshot.value;
        Map<dynamic, dynamic> requestsMap = {};
        if (rawData is Map) {
          requestsMap = rawData;
        }

        final requests = requestsMap.entries
            .where((e) => (e.value as Map)['status'] == 'pending')
            .toList();

        if (requests.isEmpty) {
          return _buildEmptyState();
        }

        return _buildRequestsList(context, requests);
      },
    );

    if (embeddedMode) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Requests'),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No pending requests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'All verification requests have been processed.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList(BuildContext context, List<MapEntry<dynamic, dynamic>> requests) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    if (isDesktop) {
      return _buildDesktopList(context, requests);
    }
    return _buildMobileList(context, requests);
  }

  Widget _buildDesktopList(BuildContext context, List<MapEntry<dynamic, dynamic>> requests) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SizedBox(width: 48),
                SizedBox(width: 16),
                Expanded(flex: 2, child: Text('NAME', style: AppTheme.tableHeader)),
                Expanded(flex: 3, child: Text('EMAIL', style: AppTheme.tableHeader)),
                Expanded(flex: 1, child: Text('STATUS', style: AppTheme.tableHeader)),
                SizedBox(width: 80, child: Text('ACTION', style: AppTheme.tableHeader)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final requestData = Map<dynamic, dynamic>.from(requests[index].value as Map);
                final String uid = requests[index].key;
                final String firstName = requestData['firstName'] ?? '';
                final String lastName = requestData['lastName'] ?? '';
                final String email = requestData['email'] ?? '';

                return _DesktopRequestRow(
                  firstName: firstName,
                  lastName: lastName,
                  email: email,
                  onTap: () => _showDesktopRequestDetails(context, uid, requestData),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(BuildContext context, List<MapEntry<dynamic, dynamic>> requests) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final requestData = Map<dynamic, dynamic>.from(requests[index].value as Map);
        final String uid = requests[index].key;
        final String firstName = requestData['firstName'] ?? '';
        final String lastName = requestData['lastName'] ?? '';
        final String email = requestData['email'] ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryOrange.withValues(alpha: 0.1),
              child: Text(
                '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}',
                style: const TextStyle(color: AppTheme.primaryOrange, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text('$firstName $lastName', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(email),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDesktopRequestDetails(context, uid, requestData),
          ),
        );
      },
    );
  }

  /// Desktop: show as a centered dialog instead of a bottom sheet
  void _showDesktopRequestDetails(BuildContext context, String uid, Map<dynamic, dynamic> data) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    if (isDesktop) {
      // Desktop: centered dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750, maxHeight: 700),
            child: _VerificationDetailContent(uid: uid, data: data, isDialog: true),
          ),
        ),
      );
    } else {
      // Mobile: bottom sheet (original behavior)
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: _VerificationDetailContent(uid: uid, data: data, isDialog: false),
          ),
        ),
      );
    }
  }

  // _handleAction and _buildImagePreview are moved into _VerificationDetailContent
}

// ─── Desktop Request Row ──────────────────────────────────────────────

class _DesktopRequestRow extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final VoidCallback onTap;

  const _DesktopRequestRow({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.onTap,
  });

  @override
  State<_DesktopRequestRow> createState() => _DesktopRequestRowState();
}

class _DesktopRequestRowState extends State<_DesktopRequestRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: _isHovered ? Border.all(color: AppTheme.cardHoverBorder) : null,
            boxShadow: _isHovered
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primaryOrange.withValues(alpha: 0.1),
                child: Text(
                  '${widget.firstName.isNotEmpty ? widget.firstName[0] : ''}${widget.lastName.isNotEmpty ? widget.lastName[0] : ''}',
                  style: const TextStyle(color: AppTheme.primaryOrange, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Text(
                  '${widget.firstName} ${widget.lastName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  widget.email,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Pending',
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                child: TextButton(
                  onPressed: widget.onTap,
                  child: const Text('Review', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Verification Detail Content (used in both Dialog and BottomSheet) ──

class _VerificationDetailContent extends StatelessWidget {
  final String uid;
  final Map<dynamic, dynamic> data;
  final bool isDialog;

  const _VerificationDetailContent({
    required this.uid,
    required this.data,
    required this.isDialog,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDialog ? 28 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Review: ${data['firstName']} ${data['lastName']}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (isDialog)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data['email'] ?? '',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const Divider(height: 32),

          // Images — side-by-side on desktop, stacked on mobile
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildLabeledImage('Selfie', data['selfie'])),
                const SizedBox(width: 16),
                Expanded(child: _buildLabeledImage('ID Front', data['idFront'])),
                const SizedBox(width: 16),
                Expanded(child: _buildLabeledImage('ID Back', data['idBack'])),
              ],
            )
          else ...[
            _buildLabeledImage('Selfie', data['selfie']),
            const SizedBox(height: 12),
            _buildLabeledImage('ID Front', data['idFront']),
            const SizedBox(height: 12),
            _buildLabeledImage('ID Back', data['idBack']),
          ],

          const SizedBox(height: 28),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => _handleAction(context, uid, true),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => _handleAction(context, uid, false),
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    label: const Text('Reject'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLabeledImage(String label, String? base64String) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        _buildImagePreview(base64String),
      ],
    );
  }

  Widget _buildImagePreview(String? base64String) {
    if (base64String == null || !base64String.contains(',')) {
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 32),
            const SizedBox(height: 8),
            Text('No image', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          base64Decode(base64String.split(',').last),
          width: double.infinity,
          fit: BoxFit.contain,
          cacheWidth: 800,
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, String uid, bool approve) async {
    final reasonController = TextEditingController();

    if (!approve) {
      final shouldReject = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Verification Request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please provide a specific reason so the applicant knows what went wrong and how to fix it:',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Rejection Reason',
                    hintText: 'e.g., ID photo was blurry, expired document, face mismatch...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Reject Request'),
            ),
          ],
        ),
      );
      if (shouldReject != true) return;
    }

    try {
      final ref = FirebaseDatabase.instance.ref();
      final String reason = reasonController.text.trim();

      await ref.child('verificationRequests').child(uid).update({
        'status': approve ? 'approved' : 'rejected',
        'rejectionReason': approve
            ? null
            : (reason.isNotEmpty ? reason : 'ID document could not be validated. Please resubmit with clear photos.'),
        'reviewedAt': ServerValue.timestamp,
      });

      if (approve) {
        await ref.child('users').child(uid).update({'isVerified': true});
      }

      final messageId = ref.child('system_messages').child(uid).push().key;
      final String noticeTitle = approve ? 'Account Verified' : 'Verification Request Update';
      final String noticeBody = approve
          ? 'Congratulations! Your Save-A-Paws account has been verified.'
          : (reason.isNotEmpty
              ? 'Your identity verification was not approved. Reason: "$reason". Please review and submit a clear, valid ID to verify your account.'
              : 'Your identity verification was not approved. Please ensure your ID photo is clear and valid, then resubmit your request.');

      await ref.child('system_messages').child(uid).child(messageId!).set({
        'title': noticeTitle,
        'body': noticeBody,
        'timestamp': ServerValue.timestamp,
        'read': false,
      });

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'Account verified successfully.' : 'Verification request rejected.'),
            backgroundColor: approve ? const Color(0xFF2E7D32) : Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
