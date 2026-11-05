import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';
import '../viewmodels/user_management_viewmodel.dart';
import 'admin_screen.dart';

class AdminUsersScreen extends StatefulWidget {
  /// When true, renders without its own Scaffold/AppBar (embedded in AdminScreen sidebar layout).
  final bool embeddedMode;

  const AdminUsersScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late UserManagementViewModel _vm;
  final TextEditingController _searchController = TextEditingController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _vm = Provider.of<UserManagementViewModel>(context, listen: false);
      _vm.listenToUsers();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Consumer<UserManagementViewModel>(
      builder: (context, vm, _) {
        if (vm.isPermissionDenied) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AdminScreen.handlePermissionDenied(context);
          });
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryOrange),
          );
        }

        if (vm.isLoading && vm.users.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryOrange),
          );
        }

        if (vm.error != null) {
          return _buildErrorState(vm.error!);
        }

        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktop = screenWidth > 900;

        return Column(
          children: [
            // Search & Filter bar
            _buildSearchFilterBar(vm),
            // Content
            Expanded(
              child: isDesktop
                  ? _buildDesktopLayout(vm)
                  : _buildMobileLayout(vm),
            ),
          ],
        );
      },
    );

    if (widget.embeddedMode) return SizedBox.expand(child: body);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _buildErrorState(String error) {
    final errStr = error.toLowerCase();
    if (errStr.contains('permission-denied') || errStr.contains('permission denied')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AdminScreen.handlePermissionDenied(context);
      });
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryOrange),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load users',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ─── Search & Filter Bar ───────────────────────────────────────────────

  Widget _buildSearchFilterBar(UserManagementViewModel vm) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth <= 768;

    final searchField = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: vm.setSearchQuery,
        decoration: InputDecoration(
          hintText: isCompact
              ? 'Search users…'
              : 'Search by name, email, or username…',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon:
              Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          suffixIcon: vm.searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear,
                      color: Colors.grey.shade400, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    vm.setSearchQuery('');
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          filled: false,
        ),
      ),
    );

    final chipsList = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['All', 'Verified', 'Unverified', 'Admin', 'Restricted', 'Banned']
            .map((status) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: status,
                    isSelected: vm.filterStatus == status,
                    onTap: () => vm.setFilterStatus(status),
                  ),
                ))
            .toList(),
      ),
    );

    if (isCompact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          children: [
            searchField,
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: chipsList,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: searchField),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: SizedBox(height: 38, child: chipsList)),
        ],
      ),
    );
  }

  // ─── Desktop Layout: Table + Detail Panel ──────────────────────────────

  Widget _buildDesktopLayout(UserManagementViewModel vm) {
    return Row(
      children: [
        // User table
        Expanded(
          flex: vm.selectedUser != null ? 3 : 5,
          child: _buildUserTable(vm),
        ),
        // Detail panel
        if (vm.selectedUser != null) ...[
          Container(width: 1, color: Colors.grey.shade200),
          Expanded(
            flex: 2,
            child: _UserDetailPanel(
              user: vm.selectedUser!,
              onClose: () => vm.selectUser(null),
              onResetPassword: () => _handlePasswordReset(vm.selectedUser!),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Mobile Layout ─────────────────────────────────────────────────────

  Widget _buildMobileLayout(UserManagementViewModel vm) {
    if (vm.selectedUser != null) {
      return _UserDetailPanel(
        user: vm.selectedUser!,
        onClose: () => vm.selectUser(null),
        onResetPassword: () => _handlePasswordReset(vm.selectedUser!),
      );
    }
    return _buildUserTable(vm);
  }

  // ─── User Table ────────────────────────────────────────────────────────

  Widget _buildUserTable(UserManagementViewModel vm) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth <= 768;

    if (vm.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              vm.searchQuery.isNotEmpty || vm.filterStatus != 'All'
                  ? 'No users match your search criteria'
                  : 'No registered users found',
              style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              vm.searchQuery.isNotEmpty || vm.filterStatus != 'All'
                  ? 'Try modifying your search query or reset the status filters.'
                  : 'Newly registered adopters, fosters, and administrators will appear here.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (vm.searchQuery.isNotEmpty || vm.filterStatus != 'All') ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  vm.setSearchQuery('');
                  vm.setFilterStatus('All');
                },
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Reset Search & Filters'),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(isCompact ? 16 : 24, 4, isCompact ? 16 : 24, 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              // Table header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border:
                      Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 40), // avatar space (matches 40px avatar)
                    const SizedBox(width: 12),
                    Expanded(
                        flex: isCompact ? 4 : 3,
                        child: const Text('NAME', style: AppTheme.tableHeader)),
                    if (!isCompact)
                      const Expanded(
                          flex: 3,
                          child: Text('EMAIL', style: AppTheme.tableHeader)),
                    Expanded(
                        flex: isCompact ? 3 : 2,
                        child: const Text('STATUS', style: AppTheme.tableHeader)),
                    const SizedBox(width: 20), // chevron space (matches 20px chevron)
                  ],
                ),
              ),
              // Table rows
              Expanded(
                child: ListView.separated(
                  itemCount: vm.users.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (context, index) {
                    final user = vm.users[index];
                    final isSelected =
                        vm.selectedUser != null && vm.selectedUser!.uid == user.uid;
                    return _UserRow(
                      key: ValueKey(user.uid),
                      user: user,
                      isSelected: isSelected,
                      onTap: () => vm.selectUser(user),
                    );
                  },
                ),
              ),
              // Footer
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border:
                      Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      vm.isFiltered
                          ? 'Showing ${vm.users.length} of ${vm.totalUsersCount} user${vm.totalUsersCount == 1 ? '' : 's'}'
                          : '${vm.users.length} registered user${vm.users.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (vm.isFiltered)
                      TextButton.icon(
                        onPressed: () {
                          _searchController.clear();
                          vm.setSearchQuery('');
                          vm.setFilterStatus('All');
                        },
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text('Reset filters', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryOrange,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Password Reset Handler ────────────────────────────────────────────

  Future<void> _handlePasswordReset(AppUser user) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Send Password Reset Email'),
        content: Text(
          'A secure password reset link will be sent to:\n${user.email}\n\nThe user can follow the link in their inbox to establish a new password.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Send Reset Email'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final vm = Provider.of<UserManagementViewModel>(context, listen: false);
    final result = await vm.sendPasswordReset(user.email);

    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Password reset email sent to ${user.email}'),
              ),
            ],
          ),
          backgroundColor: AppTheme.primaryTeal,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Error: $result')),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

// ─── Filter Chip Widget ──────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryOrange
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryOrange
                : Colors.grey.shade300,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryOrange.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ─── User Row Widget ─────────────────────────────────────────────────────

class _UserRow extends StatefulWidget {
  final AppUser user;
  final bool isSelected;
  final VoidCallback onTap;

  const _UserRow({
    super.key,
    required this.user,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth <= 768;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: widget.isSelected
              ? AppTheme.primaryOrange.withValues(alpha: 0.06)
              : _isHovered
                  ? Colors.grey.shade50
                  : Colors.white,
          child: Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.user.isAdmin
                        ? [AppTheme.primaryOrange, AppTheme.accentOrange]
                        : [AppTheme.primaryTeal, AppTheme.primaryTeal.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _getInitials(widget.user),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name
              Expanded(
                flex: isCompact ? 4 : 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.fullName.isNotEmpty
                          ? widget.user.fullName
                          : widget.user.username,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isCompact) ...[
                      Text(
                        widget.user.email,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (widget.user.username.isNotEmpty) ...[
                      Text(
                        '@${widget.user.username}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Email (Desktop only)
              if (!isCompact)
                Expanded(
                  flex: 3,
                  child: Text(
                    widget.user.email,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Status badge
              Expanded(
                flex: isCompact ? 3 : 2,
                child: _StatusBadge(status: widget.user.status),
              ),
              // Arrow
              Icon(Icons.chevron_right,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(AppUser user) {
    if (user.firstName.isNotEmpty && user.lastName.isNotEmpty) {
      return '${user.firstName[0]}${user.lastName[0]}'.toUpperCase();
    }
    if (user.username.isNotEmpty) {
      return user.username[0].toUpperCase();
    }
    return '?';
  }
}

// ─── Status Badge ────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case 'Admin':
        bgColor = AppTheme.primaryOrange.withValues(alpha: 0.1);
        textColor = AppTheme.primaryOrange;
        icon = Icons.shield;
        break;
      case 'Verified':
        bgColor = AppTheme.primaryTeal.withValues(alpha: 0.1);
        textColor = AppTheme.primaryTeal;
        icon = Icons.verified;
        break;
      case 'Banned':
        bgColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red.shade700;
        icon = Icons.block;
        break;
      case 'Restricted':
        bgColor = Colors.deepOrange.withValues(alpha: 0.12);
        textColor = Colors.deepOrange.shade800;
        icon = Icons.security_update_warning;
        break;
      default:
        bgColor = Colors.amber.withValues(alpha: 0.1);
        textColor = Colors.amber.shade800;
        icon = Icons.pending;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: textColor),
              const SizedBox(width: 4),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── User Detail Panel ───────────────────────────────────────────────────

class _UserDetailPanel extends StatefulWidget {
  final AppUser user;
  final VoidCallback onClose;
  final VoidCallback? onResetPassword;

  const _UserDetailPanel({
    required this.user,
    required this.onClose,
    this.onResetPassword,
  });

  @override
  State<_UserDetailPanel> createState() => _UserDetailPanelState();
}

class _UserDetailPanelState extends State<_UserDetailPanel> {
  bool _isUpdating = false;
  bool _isSendingReset = false;
  int _selectedTab = 0; // 0: Profile & Controls, 1: Adoption Activity

  String _getInitials() {
    if (widget.user.firstName.isNotEmpty && widget.user.lastName.isNotEmpty) {
      return '${widget.user.firstName[0]}${widget.user.lastName[0]}'.toUpperCase();
    }
    if (widget.user.username.isNotEmpty) return widget.user.username[0].toUpperCase();
    return '?';
  }

  Future<void> _updateRole(String currentRole) async {
    final roles = ['adopter', 'foster', 'volunteer', 'admin'];
    String selectedRole = currentRole.toLowerCase().trim();
    if (!roles.contains(selectedRole)) selectedRole = 'adopter';

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String tempRole = selectedRole;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Change User Role'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: roles.map((r) {
                  final isSelected = tempRole == r;
                  return ListTile(
                    title: Text(
                      r.toUpperCase(),
                      style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                    ),
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? AppTheme.primaryOrange : Colors.grey,
                    ),
                    onTap: () {
                      setDialogState(() => tempRole = r);
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, tempRole),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Update Role'),
              ),
            ],
          ),
        );
      },
    );

    if (newRole == null || newRole == currentRole.toLowerCase().trim() || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      final vm = Provider.of<UserManagementViewModel>(context, listen: false);
      await vm.updateUserRole(widget.user.uid, newRole);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Role updated to ${newRole.toUpperCase()}'),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating role: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _toggleVerification(bool currentStatus) async {
    final newStatus = !currentStatus;
    setState(() => _isUpdating = true);
    try {
      final vm = Provider.of<UserManagementViewModel>(context, listen: false);
      await vm.toggleUserVerification(widget.user.uid, currentStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? 'User verified successfully' : 'Verification revoked'),
            backgroundColor: newStatus ? const Color(0xFF2E7D32) : Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error toggling verification: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _buildRestrictionTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildCancellationLogs() {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('adoption_cancellations').child(widget.user.uid).onValue,
      builder: (context, snapshot) {
        List<Map<String, dynamic>> logs = [];
        if (snapshot.hasData && snapshot.data?.snapshot.value is Map) {
          final map = snapshot.data!.snapshot.value as Map;
          map.forEach((k, v) {
            if (v is Map) {
              final item = Map<String, dynamic>.from(v);
              item['id'] = k;
              logs.add(item);
            }
          });
          logs.sort((a, b) => ((b['timestamp'] as num?) ?? 0).compareTo((a['timestamp'] as num?) ?? 0));
        }

        final int count = logs.length > widget.user.cancelledAdoptionsCount
            ? logs.length
            : widget.user.cancelledAdoptionsCount;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: count > 0 ? Colors.red.shade50.withValues(alpha: 0.5) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: count > 0 ? Colors.red.shade200 : Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_busy, size: 18, color: count > 0 ? Colors.red : Colors.grey),
                  const SizedBox(width: 8),
                  const Text('Adoption Cancellation Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: count > 0 ? Colors.red : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count Cancelled',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (logs.isEmpty)
                Text(
                  count == 0
                      ? 'No adoption cancellations on record (0 cancellations).'
                      : '$count adoption cancellation(s) recorded.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                )
              else
                ...logs.map((l) {
                  final pet = l['petName'] ?? 'Pet';
                  final foster = l['fosterName'] ?? '';
                  final reason = l['reason'] ?? 'No reason stated';
                  final timeNum = (l['timestamp'] as num?)?.toInt();
                  String dateStr = '';
                  if (timeNum != null) {
                    final d = DateTime.fromMillisecondsSinceEpoch(timeNum);
                    dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('🐾 $pet', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            if (dateStr.isNotEmpty)
                              Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                        if (foster.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Foster: $foster', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
                        ],
                        const SizedBox(height: 4),
                        Text('Reason: "$reason"', style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRestrictionsDialog() async {
    bool isBanned = widget.user.isBanned;
    bool restrictPostings = widget.user.restrictPostings;
    bool restrictAdoptions = widget.user.restrictAdoptions;
    bool restrictReporting = widget.user.restrictReporting;
    final reasonController = TextEditingController(text: widget.user.banReason ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isBanned ? Icons.block : Icons.security,
                color: isBanned ? Colors.red : AppTheme.primaryOrange,
                size: 24,
              ),
              const SizedBox(width: 10),
              const Text('Account Suspension & Restrictions'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage moderation controls for ${widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.email}:',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // Option 1: Full Ban
                  Container(
                    decoration: BoxDecoration(
                      color: isBanned ? Colors.red.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isBanned ? Colors.red.shade300 : Colors.grey.shade300),
                    ),
                    child: SwitchListTile(
                      title: const Text('Full Account Suspension (Ban)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('User cannot log in or access the application at all', style: TextStyle(fontSize: 12)),
                      value: isBanned,
                      activeThumbColor: Colors.red,
                      onChanged: (val) {
                        setDialogState(() {
                          isBanned = val;
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Or Granular Feature Restrictions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),

                  // Option 2: Granular checkboxes
                  Opacity(
                    opacity: isBanned ? 0.4 : 1.0,
                    child: Column(
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Restrict Postings', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Prevent user from creating community feed posts or listing pets', style: TextStyle(fontSize: 11.5)),
                          value: restrictPostings,
                          onChanged: isBanned ? null : (val) => setDialogState(() => restrictPostings = val == true),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Restrict Adoptions', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Prevent user from submitting adoption requests or agreeing to terms', style: TextStyle(fontSize: 11.5)),
                          value: restrictAdoptions,
                          onChanged: isBanned ? null : (val) => setDialogState(() => restrictAdoptions = val == true),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Restrict Reporting', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Prevent user from filing stray animal or incident reports', style: TextStyle(fontSize: 11.5)),
                          value: restrictReporting,
                          onChanged: isBanned ? null : (val) => setDialogState(() => restrictReporting = val == true),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Ban / Restriction *',
                      hintText: 'e.g. Inappropriate posts, Repeated adoption cancellations, etc.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (widget.user.isBanned || widget.user.hasRestrictions)
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    isBanned = false;
                    restrictPostings = false;
                    restrictAdoptions = false;
                    restrictReporting = false;
                    reasonController.clear();
                  });
                  Navigator.pop(ctx, true);
                },
                child: const Text('Remove All Restrictions', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isBanned ? Colors.red : AppTheme.primaryOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Restrictions'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      final vm = Provider.of<UserManagementViewModel>(context, listen: false);
      await vm.updateUserRestrictions(
        widget.user.uid,
        isBanned: isBanned,
        restrictPostings: restrictPostings,
        restrictAdoptions: restrictAdoptions,
        restrictReporting: restrictReporting,
        reason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account restrictions updated successfully.'),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating restrictions: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _handlePasswordReset(String email) async {
    if (email.isEmpty || email == 'No email') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This user has no email address on file.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Password Reset Email'),
        content: Text('Send a password reset email to\n$email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Reset Email'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSendingReset = true);
    try {
      final vm = Provider.of<UserManagementViewModel>(context, listen: false);
      final error = await vm.sendPasswordReset(email);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reset email: $error'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset link sent to $email'),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? profileImage;
    final photoUrl = widget.user.profileImageUrl;
    if (photoUrl != null && photoUrl.startsWith('data:image')) {
      try {
        profileImage = MemoryImage(base64Decode(photoUrl.split(',').last));
      } catch (_) {}
    } else if (photoUrl != null && photoUrl.isNotEmpty) {
      profileImage = NetworkImage(photoUrl);
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  const Text(
                    'User Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close Details (Esc)',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClose,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),

            // Segmented Tab Switcher
            Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _selectedTab = 0),
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: _selectedTab == 0
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 16,
                              color: _selectedTab == 0
                                  ? AppTheme.primaryOrange
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Profile & Controls',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: _selectedTab == 0
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: _selectedTab == 0
                                    ? AppTheme.primaryOrange
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _selectedTab = 1),
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: _selectedTab == 1
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.pets,
                              size: 15,
                              color: _selectedTab == 1
                                  ? AppTheme.primaryOrange
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Adoption Activity',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: _selectedTab == 1
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: _selectedTab == 1
                                    ? AppTheme.primaryOrange
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _selectedTab == 0
                    ? _buildProfileTab(profileImage)
                    : _buildAdoptionActivityTab(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tab 1: Profile & Controls ─────────────────────────────────────────────

  Widget _buildProfileTab(ImageProvider? profileImage) {
    return Column(
      children: [
        // Avatar
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.user.isBanned
                  ? [Colors.red.shade400, Colors.red.shade700]
                  : widget.user.isAdmin
                      ? [AppTheme.primaryOrange, AppTheme.accentOrange]
                      : [
                          AppTheme.primaryTeal,
                          AppTheme.primaryTeal.withValues(alpha: 0.7)
                        ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            image: profileImage != null
                ? DecorationImage(
                    image: profileImage,
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: (widget.user.isBanned
                        ? Colors.red
                        : widget.user.isAdmin
                            ? AppTheme.primaryOrange
                            : AppTheme.primaryTeal)
                    .withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: profileImage == null
              ? Center(
                  child: Text(
                    _getInitials(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        // Name
        Text(
          widget.user.fullName.isNotEmpty
              ? widget.user.fullName
              : widget.user.username,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        if (widget.user.username.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '@${widget.user.username}',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
        const SizedBox(height: 8),
        _StatusBadge(status: widget.user.status),
        if (widget.user.hasRestrictions && !widget.user.isBanned) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (widget.user.restrictPostings)
                _buildRestrictionTag('No Postings', Colors.deepOrange),
              if (widget.user.restrictAdoptions)
                _buildRestrictionTag('No Adoptions', Colors.red),
              if (widget.user.restrictReporting)
                _buildRestrictionTag('No Reporting', Colors.purple),
            ],
          ),
        ],
        const SizedBox(height: 20),

        // Info cards
        _DetailInfoCard(
          icon: Icons.email_outlined,
          label: 'Email',
          value: widget.user.email,
        ),
        const SizedBox(height: 10),
        _DetailInfoCard(
          icon: Icons.person_outline,
          label: 'First Name',
          value: widget.user.firstName.isNotEmpty ? widget.user.firstName : '—',
        ),
        const SizedBox(height: 10),
        _DetailInfoCard(
          icon: Icons.person_outline,
          label: 'Last Name',
          value: widget.user.lastName.isNotEmpty ? widget.user.lastName : '—',
        ),
        const SizedBox(height: 10),
        _DetailInfoCard(
          icon: Icons.alternate_email,
          label: 'Username',
          value: widget.user.username.isNotEmpty ? widget.user.username : '—',
        ),
        const SizedBox(height: 10),
        _DetailInfoCard(
          icon: Icons.badge_outlined,
          label: 'Role',
          value: widget.user.role.toUpperCase(),
        ),
        if (widget.user.phone != null && widget.user.phone!.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DetailInfoCard(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: widget.user.phone!,
          ),
        ],
        if (widget.user.isBanned || widget.user.hasRestrictions) ...[
          const SizedBox(height: 10),
          _DetailInfoCard(
            icon: widget.user.isBanned ? Icons.block : Icons.security,
            label: widget.user.isBanned ? 'Ban Reason' : 'Restriction Reason',
            value: widget.user.banReason?.isNotEmpty == true
                ? widget.user.banReason!
                : (widget.user.isBanned ? 'Violation' : 'Feature Restriction'),
          ),
        ],

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 14),

        // ─── ADMIN CONTROLS ─────────────────────────────────
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'ADMIN CONTROLS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Action Row 1: Role & Verification
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isUpdating ? null : () => _updateRole(widget.user.role),
                icon: const Icon(Icons.manage_accounts, size: 17),
                label: const Text('Change Role'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isUpdating
                    ? null
                    : () => _toggleVerification(widget.user.isVerified),
                icon: Icon(
                    widget.user.isVerified
                        ? Icons.cancel_outlined
                        : Icons.verified,
                    size: 17),
                label: Text(
                    widget.user.isVerified ? 'Revoke Verif' : 'Verify User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.user.isVerified
                      ? Colors.orange.shade800
                      : const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Action Row 2: Restrictions & Password Reset
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isUpdating ? null : _showRestrictionsDialog,
                icon: Icon(
                  widget.user.isBanned
                      ? Icons.lock_open
                      : (widget.user.hasRestrictions
                          ? Icons.security
                          : Icons.block),
                  color: widget.user.isBanned
                      ? Colors.green
                      : (widget.user.hasRestrictions
                          ? Colors.deepOrange
                          : Colors.red),
                  size: 17,
                ),
                label: Text(
                  widget.user.isBanned
                      ? 'Unban'
                      : (widget.user.hasRestrictions
                          ? 'Restrictions'
                          : 'Ban / Restrict'),
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.user.isBanned
                      ? Colors.green
                      : (widget.user.hasRestrictions
                          ? Colors.deepOrange
                          : Colors.red),
                  side: BorderSide(
                    color: widget.user.isBanned
                        ? Colors.green
                        : (widget.user.hasRestrictions
                            ? Colors.deepOrange
                            : Colors.red),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSendingReset
                    ? null
                    : () => _handlePasswordReset(widget.user.email),
                icon: _isSendingReset
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primaryOrange),
                      )
                    : const Icon(Icons.lock_reset,
                        size: 17, color: AppTheme.primaryOrange),
                label: Text(
                  _isSendingReset ? 'Sending…' : 'Reset Pass',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryOrange,
                  side: const BorderSide(color: AppTheme.primaryOrange),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Tab 2: Adoption Activity ──────────────────────────────────────────────

  Widget _buildAdoptionActivityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary Cards Row
        StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance
              .ref()
              .child('adoption_inquiries')
              .orderByChild('adopterUid')
              .equalTo(widget.user.uid)
              .onValue,
          builder: (context, snapshot) {
            int inquiryCount = 0;
            if (snapshot.hasData && snapshot.data!.snapshot.value is Map) {
              inquiryCount = (snapshot.data!.snapshot.value as Map).length;
            }
            final cancelCount = widget.user.cancelledAdoptionsCount;

            return Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.primaryOrange.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$inquiryCount',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryOrange,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Adoption Inquiries',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cancelCount > 0
                          ? Colors.red.shade50
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cancelCount > 0
                            ? Colors.red.shade200
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$cancelCount',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: cancelCount > 0
                                ? Colors.red.shade700
                                : Colors.grey.shade700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cancellations',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cancelCount > 0
                                ? Colors.red.shade800
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        // Privacy Audit Protection Notice Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD0DCE5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined,
                  size: 16, color: Color(0xFF336688)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Privacy Protected View: Direct 1-on-1 chat conversations between adopter and foster are kept confidential to protect user communication privacy.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey.shade800,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Cancellation logs (if any)
        _buildCancellationLogs(),
        const SizedBox(height: 20),

        // Inquiries section header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_edu,
                  color: AppTheme.primaryOrange, size: 16),
            ),
            const SizedBox(width: 8),
            const Text(
              'Adoption Inquiries',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAdoptionAuditDialog(context, widget.user),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Full Audit', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryOrange,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Inquiries list for this user
        _UserAdoptionHistoryList(user: widget.user),
      ],
    );
  }
}

// ─── Detail Info Card ────────────────────────────────────────────────────

class _DetailInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailInfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Privacy-Protected Adoption History Helpers & Widgets ────────────────────


String _formatTimestamp(num? timestamp) {
  if (timestamp == null) return 'Recently';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final month = months[dt.month - 1];
  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$month ${dt.day}, ${dt.year} • $hour:$minute $period';
}

Widget _buildAdoptionStatusBadge(String status) {
  Color bg;
  Color fg;
  IconData icon;
  String label;

  switch (status.toLowerCase()) {
    case 'ready_for_pickup':
    case 'scheduled':
      bg = const Color(0xFF3F51B5).withValues(alpha: 0.12);
      fg = const Color(0xFF3F51B5);
      icon = Icons.calendar_month_rounded;
      label = 'Scheduled for Pickup';
      break;
    case 'approved':
      bg = Colors.green.withValues(alpha: 0.12);
      fg = Colors.green.shade700;
      icon = Icons.check_circle_outline;
      label = 'Foster Approved';
      break;
    case 'completed':
    case 'adopted':
      bg = AppTheme.primaryTeal.withValues(alpha: 0.12);
      fg = AppTheme.primaryTeal;
      icon = Icons.verified;
      label = 'Adopted';
      break;
    case 'rejected':
    case 'declined':
    case 'cancelled':
      bg = Colors.red.withValues(alpha: 0.12);
      fg = Colors.red.shade700;
      icon = Icons.cancel_outlined;
      label = status.toLowerCase() == 'cancelled' ? 'Cancelled' : 'Declined';
      break;
    default:
      bg = Colors.amber.withValues(alpha: 0.15);
      fg = Colors.amber.shade900;
      icon = Icons.forum_outlined;
      label = 'Pending Discussion';
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}


Widget _buildPetThumb(String imageUrl, String petId) {
  if (imageUrl.startsWith('data:image')) {
    try {
      return Image.memory(
        base64Decode(imageUrl.split(',').last),
        fit: BoxFit.cover,
        cacheWidth: 120,
        cacheHeight: 120,
        errorBuilder: (_, __, ___) => _buildThumbPlaceholder(),
      );
    } catch (_) {
      return _buildThumbPlaceholder();
    }
  }
  if (imageUrl.isNotEmpty) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildThumbPlaceholder(),
    );
  }
  return FutureBuilder<DataSnapshot>(
    future: FirebaseDatabase.instance.ref().child('adoptionCenter').child(petId).get(),
    builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data?.value is Map) {
        final data = snapshot.data!.value as Map;
        final img = data['imageUrl']?.toString() ?? '';
        if (img.startsWith('data:image')) {
          try {
            return Image.memory(
              base64Decode(img.split(',').last),
              fit: BoxFit.cover,
              cacheWidth: 120,
              cacheHeight: 120,
            );
          } catch (_) {}
        } else if (img.isNotEmpty) {
          return Image.network(img, fit: BoxFit.cover);
        }
      }
      return _buildThumbPlaceholder();
    },
  );
}

Widget _buildThumbPlaceholder() {
  return Container(
    color: Colors.grey.shade100,
    child: const Center(
      child: Icon(Icons.pets, color: Colors.grey, size: 20),
    ),
  );
}

// ─── Center Handover Verification & Quick Pass Lookup ───────────────────────

Future<void> _showCenterHandoverDialog(
  BuildContext context,
  String inquiryId,
  Map<String, dynamic> data,
) async {
  final petId = data['petId']?.toString() ?? '';
  final petName = data['petName']?.toString() ?? 'Rescued Pet';
  final petBreed = data['petBreed']?.toString() ?? '';
  final petCategory = data['petCategory']?.toString() ?? 'Pet';
  final petImageUrl = data['petImageUrl']?.toString() ?? '';
  final adopterName = data['adopterName']?.toString() ?? 'Adopter';
  final adopterUid = data['adopterUid']?.toString() ?? '';
  final adopterPhone = data['adopterPhone']?.toString() ?? '';
  final fosterId = data['fosterId']?.toString() ?? '';
  final fosterName = data['fosterName']?.toString() ?? 'Foster';
  final expectedCode = (data['adoptionCode']?.toString() ?? '').toUpperCase().trim();

  final codeController = TextEditingController();
  bool isSubmitting = false;

  try {
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
                decoration: BoxDecoration(
                  color: const Color(0xFF3F51B5).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified, color: Color(0xFF3F51B5), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Center Handover Verification',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verify the 5-character Adoption Pass presented by $adopterName at the center to complete the handover of $petName.',
                    style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  // Pet & Adopter Summary Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: _buildPetThumb(petImageUrl, petId),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                petName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                petBreed.isNotEmpty ? '$petBreed • $petCategory' : petCategory,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Adopter: $adopterName • Foster: $fosterName',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (adopterPhone.isNotEmpty)
                                Text('Phone: $adopterPhone', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Pass code display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6FD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3F51B5).withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'REGISTERED 5-CHARACTER ADOPTION PASS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: Color(0xFF3F51B5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          expectedCode.isNotEmpty ? expectedCode : 'NO CODE',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: Color(0xFF1A237E),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Confirm the 5-character ID shown by the adopter:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 5,
                    style: const TextStyle(fontFamily: 'monospace', letterSpacing: 3, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: expectedCode.isNotEmpty ? 'Enter $expectedCode' : 'Enter 5-char ID',
                      counterText: '',
                      prefixIcon: const Icon(Icons.pin, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final entered = codeController.text.trim().toUpperCase();
                      if (entered.isEmpty && expectedCode.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter the 5-character Adoption ID shown by adopter')),
                        );
                        return;
                      }
                      if (expectedCode.isNotEmpty && entered != expectedCode) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Code mismatch! Adopter pass shows $expectedCode, entered $entered'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSubmitting = true);

                      try {
                        final db = FirebaseDatabase.instance.ref();
                        final Map<String, dynamic> atomicUpdates = {
                          'adoption_inquiries/$inquiryId/status': 'completed',
                          'adoption_inquiries/$inquiryId/petRetrieved': true,
                          'adoption_inquiries/$inquiryId/isHandedOver': true,
                          'adoption_inquiries/$inquiryId/handoverCompletedAt': ServerValue.timestamp,
                          'adoption_inquiries/$inquiryId/handoverVerifiedBy': 'Center Admin',
                          'adoption_inquiries/$inquiryId/updatedAt': ServerValue.timestamp,
                        };

                        if (petId.isNotEmpty) {
                          atomicUpdates['adoptionCenter/$petId/isAdopted'] = true;
                          atomicUpdates['adoptionCenter/$petId/status'] = 'Adopted';
                          atomicUpdates['adoptionCenter/$petId/petRetrieved'] = true;
                          atomicUpdates['adoptionCenter/$petId/isHandedOver'] = true;
                          atomicUpdates['adoptionCenter/$petId/adoptedBy'] = adopterUid;
                          atomicUpdates['adoptionCenter/$petId/adoptedByName'] = adopterName;
                          atomicUpdates['adoptionCenter/$petId/adoptedAt'] = ServerValue.timestamp;
                        }

                        if (adopterUid.isNotEmpty) {
                          final adopterMsgKey = db.child('system_messages').child(adopterUid).push().key ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
                          atomicUpdates['system_messages/$adopterUid/$adopterMsgKey'] = {
                            'title': 'Handover Verified: $petName is Officially Yours!',
                            'body': 'Your 5-character Adoption ID ($expectedCode) was verified at the center. Congratulations on adopting $petName!',
                            'timestamp': ServerValue.timestamp,
                            'read': false,
                            'type': 'adoption_completed',
                            'petId': petId,
                            'petName': petName,
                            'inquiryId': inquiryId,
                          };
                        }

                        if (fosterId.isNotEmpty && fosterId != 'system') {
                          final fosterMsgKey = db.child('system_messages').child(fosterId).push().key ?? 'msg_${DateTime.now().millisecondsSinceEpoch}_f';
                          atomicUpdates['system_messages/$fosterId/$fosterMsgKey'] = {
                            'title': 'Pet Handover Completed: $petName',
                            'body': '$adopterName has claimed $petName at the Adoption Center. Thank you for fostering and saving a life!',
                            'timestamp': ServerValue.timestamp,
                            'read': false,
                            'type': 'adoption_completed',
                            'petId': petId,
                            'petName': petName,
                            'inquiryId': inquiryId,
                          };
                        }

                        await db.update(atomicUpdates);

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Handover verified! $petName is officially adopted'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to complete handover: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirm Handover & Adopt', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ),
  );
  } finally {
    codeController.dispose();
  }
}

class _UserAdoptionHistoryList extends StatelessWidget {
  final AppUser user;

  const _UserAdoptionHistoryList({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref()
          .child('adoption_inquiries')
          .orderByChild('adopterUid')
          .equalTo(user.uid)
          .onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Error loading inquiries: ${snapshot.error}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryOrange),
              ),
            ),
          );
        }

        final raw = snapshot.data?.snapshot.value;
        Map<dynamic, dynamic> inquiriesMap = {};
        if (raw is Map) {
          inquiriesMap = raw;
        }

        if (inquiriesMap.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.pets, size: 32, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'No Adoption Records',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This user has not submitted any adoption inquiries.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        final items = inquiriesMap.entries.toList();
        items.sort((a, b) {
          final tA = (a.value is Map ? (a.value['timestamp'] as num?)?.toInt() : null) ?? 0;
          final tB = (b.value is Map ? (b.value['timestamp'] as num?)?.toInt() : null) ?? 0;
          return tB.compareTo(tA);
        });

        final displayItems = items.take(3).toList();

        return Column(
          children: [
            ...displayItems.map((entry) {
              final inquiryId = entry.key.toString();
              final data = Map<String, dynamic>.from(entry.value as Map);
              return _buildInquiryCompactCard(context, inquiryId, data);
            }),
            if (items.length > 3) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _showAdoptionAuditDialog(context, user),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: Text('View all ${items.length} records'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryOrange,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildInquiryCompactCard(
    BuildContext context,
    String inquiryId,
    Map<String, dynamic> data,
  ) {
    final petId = data['petId']?.toString() ?? '';
    final petName = data['petName']?.toString() ?? 'Rescued Pet';
    final petBreed = data['petBreed']?.toString() ?? '';
    final petCategory = data['petCategory']?.toString() ?? 'Pet';
    final status = (data['status']?.toString() ?? 'pending').toLowerCase();
    final timestamp = (data['timestamp'] as num?)?.toInt();
    final petImageUrl = data['petImageUrl']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: _buildPetThumb(petImageUrl, petId),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      petName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      petBreed.isNotEmpty ? '$petBreed • $petCategory' : petCategory,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildAdoptionStatusBadge(status),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.email_outlined, size: 12, color: Colors.blueGrey.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    data['adopterEmail']?.toString() ?? user.email,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (data['adopterPhone'] != null && data['adopterPhone'].toString().trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.phone_outlined, size: 12, color: Colors.blueGrey.shade700),
                  const SizedBox(width: 3),
                  Text(
                    data['adopterPhone'].toString(),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontFamily: 'monospace'),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (data['adoptionCode'] != null && data['adoptionCode'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6FD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3F51B5).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.confirmation_number_rounded, size: 16, color: Color(0xFF3F51B5)),
                  const SizedBox(width: 8),
                  Text(
                    'Pass ID: ${data['adoptionCode'].toString().toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFF1A237E),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  if (status == 'ready_for_pickup') ...[
                    ElevatedButton.icon(
                      onPressed: () => _showCenterHandoverDialog(context, inquiryId, data),
                      icon: const Icon(Icons.check_circle_outline, size: 13),
                      label: const Text('Verify & Handover', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 0,
                      ),
                    ),
                  ] else if (status == 'completed') ...[
                    const Row(
                      children: [
                        Icon(Icons.verified, size: 13, color: Colors.green),
                        SizedBox(width: 4),
                        Text('Handover Completed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (status == 'cancelled') ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Cancelled: "${data['cancellationReason'] ?? 'Adoption cancelled by adopter'}"',
                style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Colors.red.shade900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (data['adopterAgreedTerms'] == true) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade300, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_turned_in, size: 11, color: Colors.green),
                      SizedBox(width: 3),
                      Text('Terms Accepted', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ] else if (status == 'approved') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amber.shade400, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_top, size: 11, color: Colors.amber.shade900),
                      const SizedBox(width: 3),
                      Text('Awaiting Terms Agreement', style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Text(
                'Direct Foster-Adopter Flow',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _showAdoptionAuditDialog(BuildContext context, AppUser user) {
  showDialog(
    context: context,
    builder: (dialogCtx) => _AdoptionAuditModal(user: user),
  );
}

class _AdoptionAuditModal extends StatefulWidget {
  final AppUser user;

  const _AdoptionAuditModal({required this.user});

  @override
  State<_AdoptionAuditModal> createState() => _AdoptionAuditModalState();
}

class _AdoptionAuditModalState extends State<_AdoptionAuditModal> {
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 700,
        height: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.history_edu, color: AppTheme.primaryOrange, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Adoption History Audit',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.username} • UID: ${widget.user.uid}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Privacy Notice Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD0DCE5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield, color: Color(0xFF2B5B84), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Communication Privacy Enforced',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A5F),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Direct 1-on-1 private messaging transcripts between adopter and foster are confidential and withheld from administrative audit logs. Contact and verification details remain accessible for admin verification.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade800,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Records List & Dynamic Filter Tabs
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance
                    .ref()
                    .child('adoption_inquiries')
                    .orderByChild('adopterUid')
                    .equalTo(widget.user.uid)
                    .onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
                  }

                  final raw = snapshot.data?.snapshot.value;
                  Map<dynamic, dynamic> inquiriesMap = {};
                  if (raw is Map) {
                    inquiriesMap = raw;
                  }

                  if (inquiriesMap.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.pets, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text(
                            'No adoption records found',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'This user has not submitted any adoption inquiries yet.',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  final items = inquiriesMap.entries.toList();
                  items.sort((a, b) {
                    final tA = (a.value is Map ? (a.value['timestamp'] as num?)?.toInt() : null) ?? 0;
                    final tB = (b.value is Map ? (b.value['timestamp'] as num?)?.toInt() : null) ?? 0;
                    return tB.compareTo(tA);
                  });

                  // Compute counts aligned with the full platform flow
                  int allCount = items.length;
                  int pendingCount = 0;
                  int approvedCount = 0;
                  int readyPickupCount = 0;
                  int completedCount = 0;
                  int declinedCount = 0;
                  int cancelledCount = 0;

                  for (final entry in items) {
                    final data = entry.value as Map;
                    final status = (data['status']?.toString() ?? 'pending').toLowerCase();
                    if (status == 'ready_for_pickup' || status == 'scheduled' || (data['adopterAgreedTerms'] == true && status != 'completed')) {
                      readyPickupCount++;
                    } else if (status == 'approved') {
                      approvedCount++;
                    } else if (status == 'completed' || status == 'adopted') {
                      completedCount++;
                    } else if (status == 'cancelled') {
                      cancelledCount++;
                    } else if (status == 'declined' || status == 'rejected') {
                      declinedCount++;
                    } else {
                      pendingCount++;
                    }
                  }

                  final filtered = items.where((entry) {
                    if (_selectedFilter == 'all') return true;
                    final data = entry.value as Map;
                    final status = (data['status']?.toString() ?? 'pending').toLowerCase();
                    if (_selectedFilter == 'pending') {
                      return status == 'pending' || status == 'under_review';
                    }
                    if (_selectedFilter == 'approved') {
                      return status == 'approved' && data['adopterAgreedTerms'] != true;
                    }
                    if (_selectedFilter == 'ready_for_pickup') {
                      return status == 'ready_for_pickup' || status == 'scheduled' || (data['adopterAgreedTerms'] == true && status != 'completed');
                    }
                    if (_selectedFilter == 'completed') {
                      return status == 'completed' || status == 'adopted';
                    }
                    if (_selectedFilter == 'declined' || _selectedFilter == 'rejected') {
                      return status == 'declined' || status == 'rejected';
                    }
                    if (_selectedFilter == 'cancelled') {
                      return status == 'cancelled';
                    }
                    return status == _selectedFilter;
                  }).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Filter Chips with dynamic counts
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterTab('all', 'All Applications', count: allCount),
                            const SizedBox(width: 8),
                            _buildFilterTab('pending', 'Pending Inquiries', count: pendingCount),
                            const SizedBox(width: 8),
                            _buildFilterTab('approved', 'Approved', count: approvedCount),
                            const SizedBox(width: 8),
                            _buildFilterTab('ready_for_pickup', 'Scheduled Pickup 📅', count: readyPickupCount),
                            const SizedBox(width: 8),
                            _buildFilterTab('completed', 'Adopted', count: completedCount),
                            const SizedBox(width: 8),
                            _buildFilterTab('declined', 'Declined', count: declinedCount),
                            const SizedBox(width: 8),
                            _buildFilterTab('cancelled', 'Cancelled ⚠️', count: cancelledCount),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No applications matching "$_selectedFilter"',
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final entry = filtered[index];
                                  final inquiryId = entry.key.toString();
                                  final data = Map<String, dynamic>.from(entry.value as Map);
                                  return _buildModalInquiryCard(inquiryId, data);
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(String key, String label, {int? count}) {
    final isSelected = _selectedFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModalInquiryCard(String inquiryId, Map<String, dynamic> data) {
    final petId = data['petId']?.toString() ?? '';
    final petName = data['petName']?.toString() ?? 'Rescued Pet';
    final petBreed = data['petBreed']?.toString() ?? '';
    final petCategory = data['petCategory']?.toString() ?? 'Pet';
    final fosterName = data['fosterName']?.toString() ?? 'Foster Care';
    final status = (data['status']?.toString() ?? 'pending').toLowerCase();
    final timestamp = (data['timestamp'] as num?)?.toInt();
    final petImageUrl = data['petImageUrl']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: _buildPetThumb(petImageUrl, petId),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      petName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      petBreed.isNotEmpty ? '$petBreed • $petCategory' : petCategory,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Foster: $fosterName',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _buildAdoptionStatusBadge(status),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                if (data['adopterPhone'] != null && data['adopterPhone'].toString().trim().isNotEmpty) ...[
                  const Icon(Icons.phone_outlined, size: 14, color: AppTheme.primaryOrange),
                  const SizedBox(width: 6),
                  Text(
                    'Phone: ${data['adopterPhone']}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black87),
                  ),
                  const SizedBox(width: 16),
                ],
                const Icon(Icons.email_outlined, size: 14, color: AppTheme.primaryOrange),
                const SizedBox(width: 6),
                Text(
                  'Email: ${data['adopterEmail']?.toString() ?? widget.user.email}',
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                ),
                const Spacer(),
                Text(
                  'Date: ${_formatTimestamp(timestamp)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (data['adoptionCode'] != null && data['adoptionCode'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6FD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3F51B5).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.confirmation_number_rounded, size: 20, color: Color(0xFF3F51B5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ADOPTION PASS ID',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: Color(0xFF3F51B5),
                          ),
                        ),
                        Text(
                          data['adoptionCode'].toString().toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            color: Color(0xFF1A237E),
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (status == 'ready_for_pickup' || status == 'scheduled' || (data['adopterAgreedTerms'] == true && status != 'completed')) ...[
                    ElevatedButton.icon(
                      onPressed: () => _showCenterHandoverDialog(context, inquiryId, data),
                      icon: const Icon(Icons.check_circle_outline, size: 14),
                      label: const Text('Mark Pet as Claimed / Handover Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ] else if (status == 'completed') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified, size: 14, color: Colors.green),
                          SizedBox(width: 6),
                          Text('Handover Completed & Verified', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (status == 'cancelled') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cancel, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Adoption Withdrawn / Cancelled by Adopter',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        if (data['cancellationReason'] != null && data['cancellationReason'].toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Reason: "${data['cancellationReason']}"',
                            style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.red.shade900),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (data['adopterAgreedTerms'] == true) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Terms & Responsibility Signed',
                        style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ] else if (status == 'approved') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_top, size: 14, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text(
                        'Foster Approved • Awaiting Terms Signature',
                        style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 13, color: Colors.blueGrey.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Admin Audit Only (Platform Intermediary)',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

