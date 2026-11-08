import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/user_management_viewmodel.dart';
import 'admin_verification_requests_screen.dart';
import 'admin_users_screen.dart';
import 'admin_reported_posts_screen.dart';
import 'admin_donation_screen.dart';
import 'admin_reported_pets_screen.dart';
import 'admin_pet_breeds_screen.dart';
import 'admin_support_chat_screen.dart';
import 'admin_community_screen.dart';
import 'admin_add_pet_screen.dart';
import 'admin_pet_listings_screen.dart';
import '../widgets/app_optimized_image.dart';
import 'package:firebase_database/firebase_database.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  static void handlePermissionDenied(BuildContext context) async {
    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
    final userVm = Provider.of<UserManagementViewModel>(context, listen: false);
    userVm.clearData();
    await authViewModel.signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
        arguments: 'Access denied: Permission denied by database. Administrator privileges required.',
      );
    }
  }

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyAdminAccess();
    });
  }

  Future<void> _verifyAdminAccess() async {
    if (!mounted) return;
    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
    final currentUser = authViewModel.user;
    if (currentUser == null) {
      _redirectToLogin('Please sign in to access the admin portal.');
      return;
    }

    final isAdmin = await authViewModel.checkIfAdmin(currentUser.uid);
    if (!isAdmin) {
      if (mounted) {
        Provider.of<UserManagementViewModel>(context, listen: false).clearData();
      }
      await authViewModel.signOut();
      if (mounted) {
        _redirectToLogin('Access denied. This portal is for admin users only.');
      }
    }
  }

  void _redirectToLogin(String message) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (route) => false,
      arguments: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);

    if (!authViewModel.isLoggedIn || !authViewModel.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyAdminAccess();
      });
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryOrange),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 1100;
    final isTablet = screenWidth > 600 && screenWidth <= 1100;

    // Content pages for sidebar navigation
    final pages = [
      _DashboardContent(
        onNavigateToPetListings: () => setState(() => _selectedNavIndex = 1),
        onNavigateToVerification: () => setState(() => _selectedNavIndex = 2),
        onNavigateToUsers: () => setState(() => _selectedNavIndex = 3),
        onNavigateToReportedPets: () => setState(() => _selectedNavIndex = 4),
        onNavigateToBreeds: () => setState(() => _selectedNavIndex = 5),
        onNavigateToSupportChat: () => setState(() => _selectedNavIndex = 6),
        onNavigateToReportedPosts: () => setState(() => _selectedNavIndex = 7),
        onNavigateToDonation: () => setState(() => _selectedNavIndex = 8),
        onNavigateToCommunity: () => setState(() => _selectedNavIndex = 9),
      ),
      const AdminPetListingsScreen(embeddedMode: true),
      const AdminVerificationRequestsScreen(embeddedMode: true),
      const AdminUsersScreen(embeddedMode: true),
      const AdminReportedPetsScreen(embeddedMode: true),
      const AdminPetBreedsScreen(embeddedMode: true),
      const AdminSupportChatScreen(embeddedMode: true),
      const AdminReportedPostsScreen(embeddedMode: true),
      const AdminDonationScreen(embeddedMode: true),
      const AdminCommunityScreen(embeddedMode: true),
    ];

    if (!isDesktop && !isTablet) {
      // Mobile: classic scaffold
      return _buildMobileLayout(authViewModel, pages);
    }

    // Desktop/Tablet: sidebar + content
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(authViewModel, isDesktop),
          // Content
          Expanded(
            child: Container(
              color: const Color(0xFFF5F5F8),
              child: Column(
                children: [
                  _buildTopBar(authViewModel),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.topCenter,
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      child: pages[_selectedNavIndex.clamp(0, pages.length - 1)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(AuthViewModel authViewModel, bool isDesktop) {
    return Container(
      width: isDesktop ? 260 : 72,
      decoration: const BoxDecoration(
        color: AppTheme.sidebarBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo area
          Container(
            height: 80,
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryOrange, AppTheme.accentOrange],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.pets, color: Colors.white, size: 22),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'SAVEAPAW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),

          // Nav items
          _buildNavItem(
            index: 0,
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard,
            label: 'Dashboard',
            isExpanded: isDesktop,
          ),
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref().child('adoptionCenter').onValue,
            builder: (context, snap) {
              int availableCount = 0;
              if (snap.hasData && snap.data?.snapshot.value is Map) {
                final map = snap.data!.snapshot.value as Map;
                availableCount = map.values.where((v) => v is Map && v['isAdopted'] != true).length;
              }
              return _buildNavItem(
                index: 1,
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                label: 'Shelter Pet Listings',
                isExpanded: isDesktop,
                badgeCount: availableCount,
              );
            },
          ),
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref().child('verificationRequests').orderByChild('status').equalTo('pending').onValue,
            builder: (context, snap) {
              int pendingCount = 0;
              if (snap.hasData && snap.data?.snapshot.value is Map) {
                final map = snap.data!.snapshot.value as Map;
                pendingCount = map.values.where((v) => v is Map && (v['status'] ?? '').toString().toLowerCase() == 'pending').length;
              }
              return _buildNavItem(
                index: 2,
                icon: Icons.verified_user_outlined,
                activeIcon: Icons.verified_user,
                label: 'Verification Requests',
                isExpanded: isDesktop,
                badgeCount: pendingCount,
              );
            },
          ),
          _buildNavItem(
            index: 3,
            icon: Icons.people_outline,
            activeIcon: Icons.people,
            label: 'Manage Users & Roles',
            isExpanded: isDesktop,
          ),
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref().child('reports').orderByChild('status').equalTo('Open').onValue,
            builder: (context, snap) {
              int openCount = 0;
              if (snap.hasData && snap.data?.snapshot.value is Map) {
                final map = snap.data!.snapshot.value as Map;
                openCount = map.values
                    .where((v) => v is Map && (v['status'] ?? 'Open').toString().toLowerCase() == 'open')
                    .length;
              }
              return _buildNavItem(
                index: 4,
                icon: Icons.emergency_outlined,
                activeIcon: Icons.emergency,
                label: 'Reported Pets (Rescue Hub)',
                isExpanded: isDesktop,
                badgeCount: openCount,
              );
            },
          ),
          _buildNavItem(
            index: 5,
            icon: Icons.pets_outlined,
            activeIcon: Icons.pets,
            label: 'Pet Breeds & Analytics',
            isExpanded: isDesktop,
          ),
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance
                .ref()
                .child('admin_support_queue')
                .orderByChild('status')
                .equalTo('waiting')
                .onValue,
            builder: (context, snap) {
              int waitingCount = 0;
              if (snap.hasData && snap.data?.snapshot.value is Map) {
                waitingCount = (snap.data!.snapshot.value as Map).length;
              }
              return _buildNavItem(
                index: 6,
                icon: Icons.support_agent_outlined,
                activeIcon: Icons.support_agent,
                label: 'Support Helpdesk & Queue',
                isExpanded: isDesktop,
                badgeCount: waitingCount,
              );
            },
          ),
          _buildNavItem(
            index: 7,
            icon: Icons.flag_outlined,
            activeIcon: Icons.flag,
            label: 'Reported Community Posts',
            isExpanded: isDesktop,
          ),
          _buildNavItem(
            index: 8,
            icon: Icons.volunteer_activism_outlined,
            activeIcon: Icons.volunteer_activism,
            label: 'Donation & Bank Setup',
            isExpanded: isDesktop,
          ),
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref().child('announcements').onValue,
            builder: (context, snap) {
              int alertCount = 0;
              if (snap.hasData && snap.data?.snapshot.value is Map) {
                alertCount = (snap.data!.snapshot.value as Map).length;
              }
              return _buildNavItem(
                index: 9,
                icon: Icons.campaign_outlined,
                activeIcon: Icons.campaign,
                label: 'Community & Announcements',
                isExpanded: isDesktop,
                badgeCount: alertCount,
              );
            },
          ),

          const Spacer(),

          // Logout
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 8, vertical: 20),
            child: _HoverButton(
              onTap: () async {
                final nav = Navigator.of(context);
                final userVm = Provider.of<UserManagementViewModel>(context, listen: false);
                userVm.clearData();
                await authViewModel.signOut();
                nav.pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                );
              },
              borderRadius: BorderRadius.circular(12),
              hoverColor: Colors.red.withValues(alpha: 0.15),
              child: Container(
                padding: EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: isDesktop ? 16 : 0,
                ),
                child: Row(
                  mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout, color: Colors.red, size: 20),
                    if (isDesktop) ...[
                      const SizedBox(width: 12),
                      const Text(
                        'Sign Out',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isExpanded,
    bool enabled = true,
    int? badgeCount,
  }) {
    final isActive = _selectedNavIndex == index;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 8, vertical: 2),
      child: _HoverButton(
        onTap: enabled ? () => setState(() => _selectedNavIndex = index) : null,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            vertical: 12,
            horizontal: isExpanded ? 16 : 0,
          ),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.sidebarActiveItem : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isActive ? activeIcon : icon,
                    color: isActive
                        ? AppTheme.primaryOrange
                        : enabled
                            ? Colors.white60
                            : Colors.white24,
                    size: 22,
                  ),
                  if (!isExpanded && badgeCount != null && badgeCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryOrange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : enabled
                            ? Colors.white70
                            : Colors.white30,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                if (badgeCount != null && badgeCount > 0) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ] else if (!enabled) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Soon',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AuthViewModel authViewModel) {
    final titles = [
      'Dashboard',
      'Shelter Pet Listings',
      'Verification Requests',
      'Manage Users & Roles',
      'Reported Pets (Rescue Hub)',
      'Pet Breeds & Analytics',
      'Support Helpdesk & Queue',
      'Reported Community Posts',
      'Donation & Bank Setup',
      'Community & Announcements',
    ];
    final title = _selectedNavIndex < titles.length ? titles[_selectedNavIndex] : 'Admin Portal';

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // Admin info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings, size: 18, color: AppTheme.primaryOrange),
                const SizedBox(width: 6),
                Text(
                  authViewModel.user?.email ?? 'Admin',
                  style: const TextStyle(fontSize: 13, color: AppTheme.primaryOrange, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(AuthViewModel authViewModel, List<Widget> pages) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final nav = Navigator.of(context);
              final userVm = Provider.of<UserManagementViewModel>(context, listen: false);
              userVm.clearData();
              await authViewModel.signOut();
              nav.pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: pages[_selectedNavIndex.clamp(0, pages.length - 1)],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex.clamp(0, 9),
        onDestinationSelected: (index) {
          if (index <= 9) setState(() => _selectedNavIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Shelter Pet Listings',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user),
            label: 'Verification Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Manage Users & Roles',
          ),
          NavigationDestination(
            icon: Icon(Icons.emergency_outlined),
            selectedIcon: Icon(Icons.emergency),
            label: 'Reported Pets (Rescue Hub)',
          ),
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label: 'Pet Breeds & Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Support Helpdesk & Queue',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Reported Community Posts',
          ),
          NavigationDestination(
            icon: Icon(Icons.volunteer_activism_outlined),
            selectedIcon: Icon(Icons.volunteer_activism),
            label: 'Donation & Bank Setup',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Community & Announcements',
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Dashboard Content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DashboardContent extends StatelessWidget {
  final VoidCallback onNavigateToPetListings;
  final VoidCallback onNavigateToVerification;
  final VoidCallback onNavigateToUsers;
  final VoidCallback onNavigateToReportedPosts;
  final VoidCallback onNavigateToDonation;
  final VoidCallback onNavigateToReportedPets;
  final VoidCallback onNavigateToBreeds;
  final VoidCallback onNavigateToSupportChat;
  final VoidCallback onNavigateToCommunity;
  
  const _DashboardContent({
    required this.onNavigateToPetListings,
    required this.onNavigateToVerification,
    required this.onNavigateToUsers,
    required this.onNavigateToReportedPosts,
    required this.onNavigateToDonation,
    required this.onNavigateToReportedPets,
    required this.onNavigateToBreeds,
    required this.onNavigateToSupportChat,
    required this.onNavigateToCommunity,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryOrange, AppTheme.accentOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryOrange.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome back, Admin',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manage verifications and users from your control panel.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 20),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.admin_panel_settings, size: 48, color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Live Breeds & Adoption Overview Banner
          _buildLiveAdoptionOverview(context, isDesktop),

          const SizedBox(height: 28),

          // Live Shelter Pet Listings on Dashboard
          _buildLivePetListingsSection(context, isDesktop),

          const SizedBox(height: 28),

          // Admin cards grid
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = isDesktop ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Shelter Pet Listings',
                      subtitle: 'Manage adoption catalog, view listed pets, toggle availability & edit profiles',
                      color: const Color(0xFFE65100),
                      onTap: onNavigateToPetListings,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.verified_user_outlined,
                      title: 'Verification Requests',
                      subtitle: 'Review user government IDs & face scan verifications',
                      color: AppTheme.primaryTeal,
                      onTap: onNavigateToVerification,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.people_outline,
                      title: 'Manage Users & Roles',
                      subtitle: 'Assign roles (foster/volunteer), manual verification, ban/unban',
                      color: const Color(0xFF1565C0),
                      onTap: onNavigateToUsers,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.emergency_outlined,
                      title: 'Reported Pets (Rescue Hub)',
                      subtitle: 'Coordinate live emergency rescues, track status, view locations',
                      color: Colors.redAccent,
                      onTap: onNavigateToReportedPets,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.pets_outlined,
                      title: 'Pet Breeds & Analytics',
                      subtitle: 'Dog & cat breed classification, catalog statistics & adoption rate',
                      color: const Color(0xFFE65100),
                      onTap: onNavigateToBreeds,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.support_agent_outlined,
                      title: 'Support Helpdesk & Queue',
                      subtitle: 'Answer waiting users in queue, accept tickets & live chat',
                      color: const Color(0xFF00897B),
                      onTap: onNavigateToSupportChat,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.flag_outlined,
                      title: 'Reported Community Posts',
                      subtitle: 'Review flagged community posts and take moderation action',
                      color: Colors.deepOrange,
                      onTap: onNavigateToReportedPosts,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.volunteer_activism_outlined,
                      title: 'Donation & Bank Setup',
                      subtitle: 'Configure organization QR code image, bank name & accounts',
                      color: const Color(0xFF2E7D32),
                      onTap: onNavigateToDonation,
                    ),
                  ),
                  SizedBox(
                    width: isDesktop ? cardWidth : double.infinity,
                    child: _AdminActionCard(
                      icon: Icons.campaign_outlined,
                      title: 'Community & Announcements',
                      subtitle: 'Broadcast alerts to app & devices, create official posts & manage feed',
                      color: const Color(0xFF6A1B9A),
                      onTap: onNavigateToCommunity,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveAdoptionOverview(BuildContext context, bool isDesktop) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('adoptionCenter').onValue,
      builder: (context, snapshot) {
        int totalPets = 0;
        int adoptedPets = 0;
        int dogCount = 0;
        int catCount = 0;
        final Set<String> dogBreeds = {};
        final Set<String> catBreeds = {};

        if (snapshot.hasData && snapshot.data?.snapshot.value is Map) {
          final map = snapshot.data!.snapshot.value as Map;
          totalPets = map.length;
          map.forEach((_, val) {
            if (val is Map) {
              final isAdopted = val['isAdopted'] == true;
              if (isAdopted) adoptedPets++;
              final cat = (val['category'] ?? '').toString().toLowerCase();
              final breed = (val['breed'] ?? 'Mixed / Unknown').toString().trim();
              if (cat == 'dogs') {
                dogCount++;
                if (breed.isNotEmpty) dogBreeds.add(breed);
              } else if (cat == 'cats') {
                catCount++;
                if (breed.isNotEmpty) catBreeds.add(breed);
              }
            }
          });
        }

        final availablePets = totalPets - adoptedPets;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, size: 20, color: AppTheme.primaryOrange),
                const SizedBox(width: 8),
                const Text(
                  'Adoption & Breed Analytics Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onNavigateToBreeds,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View All Breeds & Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryOrange),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = isDesktop ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _buildMiniKpi(
                        title: 'PETS ADOPTED',
                        value: '$adoptedPets',
                        subtitle: 'Completed adoptions',
                        icon: Icons.favorite_rounded,
                        accent: const Color(0xFF2E7D32),
                        bg: const Color(0xFFE8F5E9),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildMiniKpi(
                        title: 'AVAILABLE IN SHELTER',
                        value: '$availablePets',
                        subtitle: 'Looking for homes',
                        icon: Icons.home_outlined,
                        accent: const Color(0xFFE65100),
                        bg: const Color(0xFFFFF3E0),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildMiniKpi(
                        title: 'DOGS & BREEDS',
                        value: '$dogCount Dogs',
                        subtitle: '${dogBreeds.length} distinct breeds',
                        icon: Icons.pets,
                        accent: const Color(0xFF1565C0),
                        bg: const Color(0xFFE3F2FD),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildMiniKpi(
                        title: 'CATS & BREEDS',
                        value: '$catCount Cats',
                        subtitle: '${catBreeds.length} distinct breeds',
                        icon: Icons.pets,
                        accent: const Color(0xFF7B1FA2),
                        bg: const Color(0xFFF3E5F5),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniKpi({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: accent, size: 18),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF616161), letterSpacing: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: AppTheme.metricValue),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTheme.caption, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildLivePetListingsSection(BuildContext context, bool isDesktop) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('adoptionCenter').onValue,
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> petsList = [];
        if (snapshot.hasData && snapshot.data?.snapshot.value is Map) {
          final map = snapshot.data!.snapshot.value as Map;
          map.forEach((k, v) {
            if (v is Map) {
              final pet = Map<String, dynamic>.from(v);
              pet['id'] = k.toString();
              petsList.add(pet);
            }
          });
        }

        // Sort: available first, then newest
        petsList.sort((a, b) {
          final aAdopted = a['isAdopted'] == true;
          final bAdopted = b['isAdopted'] == true;
          if (aAdopted != bAdopted) return aAdopted ? 1 : -1;
          return (b['createdAt'] ?? 0).toString().compareTo((a['createdAt'] ?? 0).toString());
        });

        final displayPets = petsList.take(6).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.grid_view_rounded, size: 20, color: AppTheme.primaryOrange),
                const SizedBox(width: 8),
                Text(
                  'Live Shelter Pet Listings (${petsList.length} Total)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onNavigateToPetListings,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Manage All Pet Listings', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryOrange),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (displayPets.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.pets, size: 40, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text(
                        'No shelter pets currently listed.',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => AdminAddPetScreen.show(context),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Post First Pet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = isDesktop ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: displayPets.map((pet) {
                      final name = (pet['name'] ?? 'Pet').toString();
                      final breed = (pet['breed'] ?? 'Mixed / Rescued').toString();
                      final category = (pet['category'] ?? 'Dogs').toString();
                      final gender = (pet['gender'] ?? '').toString();
                      final age = (pet['age'] ?? '').toString();
                      final imageUrl = (pet['imageUrl'] ?? '').toString();
                      final isAdopted = pet['isAdopted'] == true;
                      final isScheduled = (pet['status'] ?? '').toString().toLowerCase().contains('scheduled') ||
                          pet['scheduledPickupDate'] != null;

                      return SizedBox(
                        width: cardWidth,
                        child: Container(
                          padding: const EdgeInsets.all(12),
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
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: _buildDashboardPetThumbnail(imageUrl),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        _buildDashboardStatusChip(isAdopted, isScheduled),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$breed • $category',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$gender • $age',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildDashboardPetThumbnail(String imageUrl) {
    return AppOptimizedImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      cacheWidth: 160,
      cacheHeight: 160,
      borderRadius: BorderRadius.circular(8),
    );
  }

  Widget _buildDashboardStatusChip(bool isAdopted, bool isScheduled) {
    if (isAdopted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(6)),
        child: Text(
          'Adopted',
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
        ),
      );
    }
    if (isScheduled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
        child: Text(
          'Scheduled',
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text(
        'Available',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.green.shade700),
      ),
    );
  }
}

// â”€â”€â”€ Hoverâ€‘enabled Admin Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AdminActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _HoverButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      hoverColor: color.withValues(alpha: 0.04),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
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
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey.shade400, size: 16),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ Reusable Hover Button Widget â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color hoverColor;

  const _HoverButton({
    required this.child,
    required this.onTap,
    required this.borderRadius,
    required this.hoverColor,
  });

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered ? widget.hoverColor : Colors.transparent,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

