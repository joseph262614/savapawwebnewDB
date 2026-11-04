import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_theme.dart';
import 'admin_add_pet_screen.dart';

class AdminPetListingsScreen extends StatefulWidget {
  final bool embeddedMode;

  const AdminPetListingsScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminPetListingsScreen> createState() => _AdminPetListingsScreenState();
}

class _AdminPetListingsScreenState extends State<AdminPetListingsScreen> {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<DatabaseEvent>? _usersSubscription;
  Map<String, String> _userDisplayNames = {};
  final Set<String> _pendingPetUpdates = {};

  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'available', 'adopted', 'scheduled'
  String _categoryFilter = 'all'; // 'all', 'dogs', 'cats', 'other'
  String _sortBy = 'newest'; // 'newest', 'name', 'breed'

  @override
  void initState() {
    super.initState();
    _usersSubscription = _db.ref().child('users').onValue.listen((event) {
      if (mounted && event.snapshot.exists && event.snapshot.value is Map) {
        final usersMap = event.snapshot.value as Map;
        final Map<String, String> resolved = {};
        usersMap.forEach((uid, val) {
          if (val is Map) {
            final fName = (val['firstName'] ?? '').toString().trim();
            final lName = (val['lastName'] ?? '').toString().trim();
            final uName = (val['username'] ?? '').toString().trim();
            final fullName = ('$fName $lName').trim();
            final role = (val['role'] ?? '').toString().toLowerCase();
            final roleSuffix = role == 'foster' ? ' (Foster)' : (role == 'admin' ? ' (Admin)' : '');

            if (fullName.isNotEmpty) {
              resolved[uid.toString()] = '$fullName$roleSuffix';
            } else if (uName.isNotEmpty) {
              resolved[uid.toString()] = '@$uName$roleSuffix';
            }
          }
        });
        setState(() => _userDisplayNames = resolved);
      }
    });
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _getPosterDisplayName(_ShelterPet pet) {
    if (pet.fosterName.isNotEmpty &&
        pet.fosterName != 'Save-A-Paws Admin' &&
        pet.fosterName != 'Admin Center') {
      return pet.fosterName;
    }
    if (pet.fosterId.isNotEmpty && _userDisplayNames.containsKey(pet.fosterId)) {
      return _userDisplayNames[pet.fosterId]!;
    }
    if (pet.fosterId.isNotEmpty && pet.fosterId != 'admin_center') {
      return 'Foster (${pet.fosterId.length > 6 ? pet.fosterId.substring(0, 6) : pet.fosterId})';
    }
    return 'Save-A-Paws Admin Center';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: widget.embeddedMode
          ? null
          : AppBar(
              title: const Text('Shelter Pet Listings Management'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 1,
            ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _db.ref().child('adoptionCenter').onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text('Failed to load pet listings: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                ],
              ),
            );
          }

          final List<_ShelterPet> allPets = [];
          if (snapshot.hasData && snapshot.data?.snapshot.value is Map) {
            final petsMap = snapshot.data!.snapshot.value as Map;
            petsMap.forEach((key, val) {
              if (val is Map) {
                allPets.add(_ShelterPet.fromMap(key.toString(), val));
              }
            });
          }

          // Sort pets
          if (_sortBy == 'newest') {
            allPets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } else if (_sortBy == 'name') {
            allPets.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else if (_sortBy == 'breed') {
            allPets.sort((a, b) => a.breed.toLowerCase().compareTo(b.breed.toLowerCase()));
          }

          // Filter
          final filteredPets = allPets.where((pet) {
            // Category
            if (_categoryFilter != 'all') {
              final cat = pet.category.toLowerCase();
              if (_categoryFilter == 'dogs' && cat != 'dogs') return false;
              if (_categoryFilter == 'cats' && cat != 'cats') return false;
              if (_categoryFilter == 'other' && (cat == 'dogs' || cat == 'cats')) return false;
            }

            // Status
            if (_statusFilter == 'available' && pet.isAdopted) return false;
            if (_statusFilter == 'adopted' && !pet.isAdopted) return false;
            if (_statusFilter == 'scheduled' && !pet.isScheduled) return false;

            // Search
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final matchesName = pet.name.toLowerCase().contains(q);
              final matchesBreed = pet.breed.toLowerCase().contains(q);
              final matchesLocation = pet.locationAddress.toLowerCase().contains(q);
              final matchesFoster = pet.fosterName.toLowerCase().contains(q);
              return matchesName || matchesBreed || matchesLocation || matchesFoster;
            }

            return true;
          }).toList();

          // Metrics
          final totalPets = allPets.length;
          final adoptedCount = allPets.where((p) => p.isAdopted).length;
          final availableCount = totalPets - adoptedCount;
          final scheduledCount = allPets.where((p) => p.isScheduled).length;
          final dogsCount = allPets.where((p) => p.category.toLowerCase() == 'dogs').length;
          final catsCount = allPets.where((p) => p.category.toLowerCase() == 'cats').length;

          return Padding(
            padding: EdgeInsets.all(isDesktop ? 28.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header with Title and "Post a Pet" action
                _buildHeader(isDesktop),

                const SizedBox(height: 18),

                // Metrics KPI Row
                _buildMetricsRow(
                  isDesktop: isDesktop,
                  total: totalPets,
                  available: availableCount,
                  adopted: adoptedCount,
                  scheduled: scheduledCount,
                  dogs: dogsCount,
                  cats: catsCount,
                ),

                const SizedBox(height: 20),

                // Controls: Search, Category, Status, Sort
                _buildFilterControls(isDesktop),

                const SizedBox(height: 16),

                // Pet Listings Table / Cards List
                Expanded(
                  child: filteredPets.isEmpty
                      ? _buildEmptyState()
                      : isDesktop
                          ? _buildDesktopTable(filteredPets)
                          : _buildMobileCardsList(filteredPets),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primaryOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.pets, color: AppTheme.primaryOrange, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Shelter Pet Listings & Catalog',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3),
              ),
              const SizedBox(height: 2),
              Text(
                'Manage all pets available for adoption, update profiles, toggle adoption status, and post new shelter pets.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => AdminAddPetScreen.show(context),
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('Post New Pet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryOrange,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow({
    required bool isDesktop,
    required int total,
    required int available,
    required int adopted,
    required int scheduled,
    required int dogs,
    required int cats,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = isDesktop ? (constraints.maxWidth - 48) / 5 : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'TOTAL LISTED',
                value: '$total Pets',
                subtitle: 'In shelter database',
                icon: Icons.inventory_2_outlined,
                accentColor: const Color(0xFF1565C0),
                bgColor: const Color(0xFFE3F2FD),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'AVAILABLE NOW',
                value: '$available',
                subtitle: 'Looking for homes',
                icon: Icons.check_circle_outline,
                accentColor: const Color(0xFF2E7D32),
                bgColor: const Color(0xFFE8F5E9),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'ADOPTED',
                value: '$adopted',
                subtitle: 'Successfully placed',
                icon: Icons.verified_user_outlined,
                accentColor: const Color(0xFF6A1B9A),
                bgColor: const Color(0xFFF3E5F5),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'SCHEDULED PICKUP',
                value: '$scheduled',
                subtitle: 'Awaiting retriever visit',
                icon: Icons.calendar_today_outlined,
                accentColor: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'SPECIES SPLIT',
                value: '$dogs Dogs • $cats Cats',
                subtitle: 'Catalog breakdown',
                icon: Icons.category_outlined,
                accentColor: const Color(0xFF00695C),
                bgColor: const Color(0xFFE0F2F1),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
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
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildFilterControls(bool isDesktop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search box
          SizedBox(
            width: isDesktop ? 280 : double.infinity,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'Search pet name, breed, location...',
                hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Category Chips
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Species: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(width: 4),
              _buildCategoryChip('All', 'all'),
              const SizedBox(width: 4),
              _buildCategoryChip('🐶 Dogs', 'dogs'),
              const SizedBox(width: 4),
              _buildCategoryChip('🐱 Cats', 'cats'),
              const SizedBox(width: 4),
              _buildCategoryChip('🐾 Other', 'other'),
            ],
          ),

          // Status Filter Chips
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Status: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(width: 4),
              _buildStatusChip('All', 'all'),
              const SizedBox(width: 4),
              _buildStatusChip('Available', 'available'),
              const SizedBox(width: 4),
              _buildStatusChip('Adopted', 'adopted'),
            ],
          ),

          // Sort dropdown
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sort: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(width: 4),
              DropdownButton<String>(
                value: _sortBy,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                items: const [
                  DropdownMenuItem(value: 'newest', child: Text('Newest First')),
                  DropdownMenuItem(value: 'name', child: Text('Name (A-Z)')),
                  DropdownMenuItem(value: 'breed', child: Text('Breed (A-Z)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _sortBy = val);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String value) {
    final isSelected = _categoryFilter == value;
    return InkWell(
      onTap: () => setState(() => _categoryFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryOrange.withValues(alpha: 0.12) : const Color(0xFFF0F1F4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.primaryOrange : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryOrange.withValues(alpha: 0.12) : const Color(0xFFF0F1F4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.primaryOrange : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool hasActiveFilters = _searchQuery.isNotEmpty || _statusFilter != 'all' || _categoryFilter != 'all';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Text(
            hasActiveFilters
                ? 'No pet listings match your search or filters'
                : 'No pet listings found in shelter catalog',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            hasActiveFilters
                ? 'Try clearing your search terms or adjusting the category and status filters.'
                : 'Get started by publishing your first pet listing to the adoption center.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasActiveFilters) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _statusFilter = 'all';
                      _categoryFilter = 'all';
                    });
                  },
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Reset Filters'),
                ),
                const SizedBox(width: 10),
              ],
              ElevatedButton.icon(
                onPressed: () => AdminAddPetScreen.show(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Post a Pet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(List<_ShelterPet> pets) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width > 900
                    ? MediaQuery.of(context).size.width - 280
                    : 900,
              ),
              child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
            dataRowMinHeight: 70,
            dataRowMaxHeight: 75,
            horizontalMargin: 20,
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('PET', style: AppTheme.tableHeader)),
              DataColumn(label: Text('CATEGORY & BREED', style: AppTheme.tableHeader)),
              DataColumn(label: Text('AGE / GENDER', style: AppTheme.tableHeader)),
              DataColumn(label: Text('HEALTH RECORD', style: AppTheme.tableHeader)),
              DataColumn(label: Text('STATUS', style: AppTheme.tableHeader)),
              DataColumn(label: Text('POSTED BY', style: AppTheme.tableHeader)),
              DataColumn(label: Text('ACTIONS', style: AppTheme.tableHeader)),
            ],
            rows: pets.map((pet) {
              final isPoster = pet.fosterId.isNotEmpty && pet.fosterId == FirebaseAuth.instance.currentUser?.uid;
              return DataRow(
                cells: [
                  // Pet (Photo + Name)
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: _buildThumbnail(pet.imageUrl),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(
                                pet.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (pet.locationAddress.isNotEmpty)
                              SizedBox(
                                width: 140,
                                child: Text(
                                  pet.locationAddress,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Category & Breed
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            pet.breed,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pet.category,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Age / Gender
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pet.gender.toLowerCase() == 'male' ? Icons.male : Icons.female,
                          size: 16,
                          color: pet.gender.toLowerCase() == 'male' ? Colors.blue : Colors.pink,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${pet.gender} • ${pet.age}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),

                  // Health Record
                  DataCell(
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (pet.isVaccinated)
                          _buildMiniBadge('Vaccinated', Colors.green)
                        else
                          _buildMiniBadge('No Vaccine', Colors.grey),
                        if (pet.isDewormed) _buildMiniBadge('Dewormed', Colors.teal),
                        if (pet.isNeutered) _buildMiniBadge('Neutered', Colors.indigo),
                        if (pet.isMicrochipped) _buildMiniBadge('Microchipped', Colors.deepPurple),
                      ],
                    ),
                  ),

                  // Status
                  DataCell(_buildStatusBadge(pet)),

                  // Posted By
                  DataCell(
                    SizedBox(
                      width: 140,
                      child: Text(
                        _getPosterDisplayName(pet),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  // Actions
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Details
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF1565C0)),
                          tooltip: 'View Pet Details',
                          onPressed: () => _showPetDetailsDialog(pet),
                        ),
                        // Quick Status Toggle
                        Builder(
                          builder: (context) {
                            final isPending = _pendingPetUpdates.contains(pet.id);
                            return IconButton(
                              icon: isPending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                                    )
                                  : Icon(
                                      isPoster
                                          ? (pet.isAdopted ? Icons.undo : Icons.check_circle_outline)
                                          : Icons.lock_outline,
                                      size: 18,
                                      color: isPoster
                                          ? (pet.isAdopted ? Colors.deepOrange : Colors.green)
                                          : Colors.grey.shade400,
                                    ),
                              tooltip: isPending
                                  ? 'Updating status...'
                                  : isPoster
                                      ? (pet.isAdopted ? 'Mark Available' : 'Mark Adopted')
                                      : 'Only the poster can mark adoption status',
                              onPressed: isPending
                                  ? null
                                  : isPoster
                                      ? () => _toggleAdoptionStatus(pet)
                                      : () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Cannot mark "${pet.name}". Only the user who posted this pet can change its adoption status.'),
                                              backgroundColor: Colors.orange.shade800,
                                            ),
                                          );
                                        },
                            );
                          },
                        ),
                        // Edit Pet - only allowed if poster
                        if (isPoster)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.black87),
                            tooltip: 'Edit Pet Info',
                            onPressed: () => _showEditPetDialog(pet),
                          )
                        else
                          Tooltip(
                            message: 'Only the user who posted this pet can edit its info',
                            child: IconButton(
                              icon: Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade400),
                              tooltip: 'Only the poster can edit this pet',
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Cannot edit "${pet.name}". Only the user who posted this pet can edit its info.'),
                                    backgroundColor: Colors.orange.shade800,
                                  ),
                                );
                              },
                            ),
                          ),
                        // Delete Pet
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          tooltip: 'Delete Pet Listing',
                          onPressed: () => _confirmDeletePet(pet),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCardsList(List<_ShelterPet> pets) {
    return ListView.builder(
      itemCount: pets.length,
      padding: const EdgeInsets.only(bottom: 24),
      itemBuilder: (context, index) {
        final pet = pets[index];
        final isPoster = pet.fosterId.isNotEmpty && pet.fosterId == FirebaseAuth.instance.currentUser?.uid;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: _buildThumbnail(pet.imageUrl),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  pet.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildStatusBadge(pet),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${pet.breed} • ${pet.gender} • ${pet.age}',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Posted by: ${_getPosterDisplayName(pet)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (pet.isVaccinated) _buildMiniBadge('Vaccinated', Colors.green),
                    if (pet.isDewormed) _buildMiniBadge('Dewormed', Colors.teal),
                    if (pet.isNeutered) _buildMiniBadge('Neutered', Colors.indigo),
                    if (pet.isMicrochipped) _buildMiniBadge('Microchipped', Colors.deepPurple),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showPetDetailsDialog(pet),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Details'),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final isPending = _pendingPetUpdates.contains(pet.id);
                        return TextButton.icon(
                          onPressed: isPending
                              ? null
                              : isPoster
                                  ? () => _toggleAdoptionStatus(pet)
                                  : () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Cannot mark "${pet.name}". Only the user who posted this pet can change its adoption status.'),
                                          backgroundColor: Colors.orange.shade800,
                                        ),
                                      );
                                    },
                          icon: isPending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                                )
                              : Icon(
                                  isPoster ? (pet.isAdopted ? Icons.undo : Icons.check) : Icons.lock_outline,
                                  size: 16,
                                ),
                          label: Text(
                            isPending
                                ? 'Updating...'
                                : pet.isAdopted
                                    ? 'Mark Available'
                                    : 'Mark Adopted',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: isPoster
                                ? (pet.isAdopted ? Colors.orange : Colors.green)
                                : Colors.grey.shade400,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    if (isPoster)
                      TextButton.icon(
                        onPressed: () => _showEditPetDialog(pet),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      )
                    else
                      Tooltip(
                        message: 'Only the user who posted this pet can edit its info',
                        child: TextButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Cannot edit "${pet.name}". Only the user who posted this pet can edit its info.'),
                                backgroundColor: Colors.orange.shade800,
                              ),
                            );
                          },
                          icon: const Icon(Icons.lock_outline, size: 15, color: Colors.grey),
                          label: Text('Edit', style: TextStyle(color: Colors.grey.shade400)),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      onPressed: () => _confirmDeletePet(pet),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.pets, color: Colors.grey, size: 28),
      );
    }
    if (imageUrl.startsWith('data:image')) {
      try {
        final commaIdx = imageUrl.indexOf(',');
        final base64Str = commaIdx != -1 ? imageUrl.substring(commaIdx + 1) : imageUrl;
        return Image.memory(
          base64Decode(base64Str),
          fit: BoxFit.cover,
          cacheWidth: 160,
          cacheHeight: 160,
        );
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

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStatusBadge(_ShelterPet pet) {
    if (pet.isAdopted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.purple.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.purple.shade700, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(
              'Adopted',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
            ),
          ],
        ),
      );
    }

    if (pet.isScheduled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.blue.shade700, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(
              'Pickup Scheduled',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.green.shade700, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(
            'Available',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAdoptionStatus(_ShelterPet pet) async {
    if (_pendingPetUpdates.contains(pet.id)) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (pet.fosterId.isNotEmpty && pet.fosterId != currentUid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot mark "${pet.name}". Only the user who posted this pet can change its adoption status.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _pendingPetUpdates.add(pet.id);
      });
    }

    final nextAdopted = !pet.isAdopted;
    try {
      await _db.ref().child('adoptionCenter').child(pet.id).update({
        'isAdopted': nextAdopted,
        'status': nextAdopted ? 'adopted' : 'Available',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pet.name} is now marked as ${nextAdopted ? 'Adopted' : 'Available'}!'),
            backgroundColor: nextAdopted ? Colors.purple : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingPetUpdates.remove(pet.id);
        });
      }
    }
  }

  void _confirmDeletePet(_ShelterPet pet) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${pet.name}" listing?'),
        content: const Text(
          'Are you sure you want to remove this pet listing from the Shelter Adoption Center? This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _db.ref().child('adoptionCenter').child(pet.id).remove();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${pet.name} listing deleted successfully.'), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting pet: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete Pet'),
          ),
        ],
      ),
    );
  }

  void _showPetDetailsDialog(_ShelterPet pet) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(width: 80, height: 80, child: _buildThumbnail(pet.imageUrl)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pet.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('${pet.breed} • ${pet.gender} • ${pet.age}', style: TextStyle(color: Colors.grey.shade600)),
                        const SizedBox(height: 6),
                        _buildStatusBadge(pet),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 10),
              const Text('Medical & Health Records:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHealthChip('Vaccinated', pet.isVaccinated),
                  _buildHealthChip('Dewormed', pet.isDewormed),
                  _buildHealthChip('Neutered / Spayed', pet.isNeutered),
                  _buildHealthChip('Microchipped', pet.isMicrochipped),
                  _buildHealthChip('Vitamin Shots', pet.hasVitaminShots),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Pet Story & Bio:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                pet.description.isNotEmpty ? pet.description : 'No detailed description provided.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Posted by: ${_getPosterDisplayName(pet)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pet.locationAddress.isNotEmpty ? pet.locationAddress : 'Save-A-Paws Shelter Facility',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditPetDialog(pet);
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit Details'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthChip(String label, bool isTrue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isTrue ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isTrue ? Colors.green.shade300 : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isTrue ? Icons.check_circle : Icons.cancel_outlined, size: 14, color: isTrue ? Colors.green : Colors.grey),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isTrue ? Colors.green.shade800 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPetDialog(_ShelterPet pet) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (pet.fosterId.isNotEmpty && pet.fosterId != currentUid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot edit "${pet.name}". Only the foster user who posted this pet can edit its info.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
      return;
    }

    final nameCtrl = TextEditingController(text: pet.name);
    final breedCtrl = TextEditingController(text: pet.breed);
    final ageCtrl = TextEditingController(text: pet.age);
    final descCtrl = TextEditingController(text: pet.description);
    final locationCtrl = TextEditingController(text: pet.locationAddress);
    String selectedCategory = pet.category;
    String selectedGender = pet.gender;
    bool isVaccinated = pet.isVaccinated;
    bool isDewormed = pet.isDewormed;
    bool isNeutered = pet.isNeutered;
    bool isMicrochipped = pet.isMicrochipped;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 580,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Edit "${pet.name}" Profile', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Pet Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: ['Dogs', 'Cats', 'Birds', 'Other'].contains(selectedCategory) ? selectedCategory : 'Dogs',
                            decoration: const InputDecoration(labelText: 'Species', border: OutlineInputBorder()),
                            items: ['Dogs', 'Cats', 'Birds', 'Other']
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) => setDlgState(() => selectedCategory = v ?? 'Dogs'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: ['Male', 'Female'].contains(selectedGender) ? selectedGender : 'Male',
                            decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                            items: ['Male', 'Female']
                                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                .toList(),
                            onChanged: (v) => setDlgState(() => selectedGender = v ?? 'Male'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: breedCtrl,
                            decoration: const InputDecoration(labelText: 'Breed', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: ageCtrl,
                            decoration: const InputDecoration(labelText: 'Age (e.g. 2 years)', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Bio / Description', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(labelText: 'Shelter Location / Address', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    const Text('Medical Checklist:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Vaccinated'),
                      value: isVaccinated,
                      onChanged: (v) => setDlgState(() => isVaccinated = v ?? false),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dewormed'),
                      value: isDewormed,
                      onChanged: (v) => setDlgState(() => isDewormed = v ?? false),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Neutered / Spayed'),
                      value: isNeutered,
                      onChanged: (v) => setDlgState(() => isNeutered = v ?? false),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Microchipped'),
                      value: isMicrochipped,
                      onChanged: (v) => setDlgState(() => isMicrochipped = v ?? false),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryOrange, foregroundColor: Colors.white),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setDlgState(() => isSaving = true);
                                  try {
                                    await _db.ref().child('adoptionCenter').child(pet.id).update({
                                      'name': nameCtrl.text.trim(),
                                      'category': selectedCategory,
                                      'gender': selectedGender,
                                      'breed': breedCtrl.text.trim(),
                                      'age': ageCtrl.text.trim(),
                                      'description': descCtrl.text.trim(),
                                      'locationAddress': locationCtrl.text.trim(),
                                      'isVaccinated': isVaccinated,
                                      'vaccine': isVaccinated,
                                      'isDewormed': isDewormed,
                                      'dewormed': isDewormed,
                                      'isNeutered': isNeutered,
                                      'neutered': isNeutered,
                                      'isMicrochipped': isMicrochipped,
                                      'microchip': isMicrochipped,
                                    });
                                    if (context.mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${nameCtrl.text.trim()} updated successfully!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setDlgState(() => isSaving = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error updating pet: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Save Changes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Model ───────────────────────────────────────────────────────────────────

class _ShelterPet {
  final String id;
  final String name;
  final String breed;
  final String category;
  final String gender;
  final String age;
  final String description;
  final String imageUrl;
  final String fosterId;
  final String fosterName;
  final String locationAddress;
  final bool isAdopted;
  final bool isScheduled;
  final bool isVaccinated;
  final bool isDewormed;
  final bool isMicrochipped;
  final bool isNeutered;
  final bool hasVitaminShots;
  final int createdAt;

  _ShelterPet({
    required this.id,
    required this.name,
    required this.breed,
    required this.category,
    required this.gender,
    required this.age,
    required this.description,
    required this.imageUrl,
    required this.fosterId,
    required this.fosterName,
    required this.locationAddress,
    required this.isAdopted,
    required this.isScheduled,
    required this.isVaccinated,
    required this.isDewormed,
    required this.isMicrochipped,
    required this.isNeutered,
    required this.hasVitaminShots,
    required this.createdAt,
  });

  factory _ShelterPet.fromMap(String id, Map data) {
    final statusStr = (data['status'] ?? '').toString().toLowerCase();
    final isAdopted = data['isAdopted'] == true || statusStr == 'adopted' || statusStr == 'completed';
    final isScheduled = statusStr.contains('scheduled') || data['scheduledPickupDate'] != null;

    int parseCreatedAt() {
      final c = data['createdAt'];
      if (c is int) return c;
      if (c is num) return c.toInt();
      return 0;
    }

    return _ShelterPet(
      id: id,
      name: (data['name'] ?? 'Pet').toString(),
      breed: (data['breed'] ?? 'Mixed / Rescued').toString(),
      category: (data['category'] ?? 'Dogs').toString(),
      gender: (data['gender'] ?? 'Unknown').toString(),
      age: (data['age'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      fosterId: (data['fosterId'] ?? '').toString(),
      fosterName: (data['fosterName'] ?? '').toString(),
      locationAddress: (data['locationAddress'] ?? '').toString(),
      isAdopted: isAdopted,
      isScheduled: isScheduled,
      isVaccinated: data['isVaccinated'] == true || data['vaccine'] == true,
      isDewormed: data['isDewormed'] == true || data['dewormed'] == true,
      isMicrochipped: data['isMicrochipped'] == true || data['microchip'] == true,
      isNeutered: data['isNeutered'] == true || data['neutered'] == true,
      hasVitaminShots: data['hasVitaminShots'] == true || data['vitaminshots'] == true,
      createdAt: parseCreatedAt(),
    );
  }
}
