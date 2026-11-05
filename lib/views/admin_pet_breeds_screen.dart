import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import 'admin_add_pet_screen.dart';

class AdminPetBreedsScreen extends StatefulWidget {
  final bool embeddedMode;

  const AdminPetBreedsScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminPetBreedsScreen> createState() => _AdminPetBreedsScreenState();
}

class _AdminPetBreedsScreenState extends State<AdminPetBreedsScreen> with SingleTickerProviderStateMixin {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  late TabController _tabController;

  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'available', 'adopted'
  String _sortBy = 'count'; // 'count', 'adopted', 'name'
  String? _expandedBreed;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
              title: const Text('Pet Breeds & Adoption Analytics'),
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
                  Text('Failed to load pets: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                ],
              ),
            );
          }

          final List<_PetItem> allPets = [];
          if (snapshot.hasData && snapshot.data?.snapshot.value is Map) {
            final petsMap = snapshot.data!.snapshot.value as Map;
            petsMap.forEach((key, val) {
              if (val is Map) {
                allPets.add(_PetItem.fromMap(key.toString(), val));
              }
            });
          }

          // Compute analytics
          final totalPets = allPets.length;
          final adoptedPets = allPets.where((p) => p.isAdopted).length;
          final availablePets = totalPets - adoptedPets;
          final adoptionRate = totalPets > 0 ? ((adoptedPets / totalPets) * 100).toStringAsFixed(1) : '0';

          final dogsList = allPets.where((p) => p.category.toLowerCase() == 'dogs').toList();
          final catsList = allPets.where((p) => p.category.toLowerCase() == 'cats').toList();
          final otherList = allPets
              .where((p) => p.category.toLowerCase() != 'dogs' && p.category.toLowerCase() != 'cats')
              .toList();

          final dogBreeds = _groupBreeds(dogsList);
          final catBreeds = _groupBreeds(catsList);
          final otherBreeds = _groupBreeds(otherList);

          return Padding(
            padding: EdgeInsets.all(isDesktop ? 28.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header with Title and Copy Report Action
                _buildHeader(isDesktop, allPets, totalPets, adoptedPets, availablePets, dogBreeds.length, catBreeds.length),

                const SizedBox(height: 18),

                // KPI Stat Cards Grid
                _buildKpiSection(
                  isDesktop: isDesktop,
                  totalPets: totalPets,
                  adoptedPets: adoptedPets,
                  availablePets: availablePets,
                  adoptionRate: adoptionRate,
                  totalDogs: dogsList.length,
                  adoptedDogs: dogsList.where((p) => p.isAdopted).length,
                  dogBreedCount: dogBreeds.length,
                  totalCats: catsList.length,
                  adoptedCats: catsList.where((p) => p.isAdopted).length,
                  catBreedCount: catBreeds.length,
                ),

                const SizedBox(height: 22),

                // Controls: Search, Status Filter, Sort By
                _buildFilterControls(isDesktop),

                const SizedBox(height: 14),

                // Tabs for Dogs, Cats, and All / Others
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppTheme.primaryOrange,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: AppTheme.primaryOrange,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    tabs: [
                      Tab(
                        text: 'Dogs (${dogsList.length} pets • ${dogBreeds.length} breeds)',
                      ),
                      Tab(
                        text: 'Cats (${catsList.length} pets • ${catBreeds.length} breeds)',
                      ),
                      Tab(
                        text: 'All / Others (${otherList.length} pets)',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Breed Lists inside TabBarView
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBreedGrid(
                        breeds: dogBreeds,
                        speciesLabel: 'Dog',
                        defaultSpeciesIcon: Icons.pets,
                        accentColor: const Color(0xFFE65100),
                      ),
                      _buildBreedGrid(
                        breeds: catBreeds,
                        speciesLabel: 'Cat',
                        defaultSpeciesIcon: Icons.cruelty_free,
                        accentColor: const Color(0xFF6A1B9A),
                      ),
                      _buildBreedGrid(
                        breeds: otherBreeds,
                        speciesLabel: 'Other Animal',
                        defaultSpeciesIcon: Icons.flutter_dash,
                        accentColor: const Color(0xFF00695C),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    bool isDesktop,
    List<_PetItem> allPets,
    int totalPets,
    int adoptedPets,
    int availablePets,
    int dogBreedCount,
    int catBreedCount,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primaryOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.insights_rounded, color: AppTheme.primaryOrange, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pet Breed Classification & Adoption Analytics',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3),
              ),
              const SizedBox(height: 2),
              Text(
                'Real-time breed tracking for cats and dogs, adoption velocity, and center inventory.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (isDesktop) ...[
          ElevatedButton.icon(
            onPressed: () => _showQuickPassLookupDialog(context),
            icon: const Icon(Icons.confirmation_number_outlined, size: 16),
            label: const Text('Verify Adoption Pass', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F51B5),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => AdminAddPetScreen.show(context),
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('Post a Pet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showSummaryReportDialog(
              context,
              allPets: allPets,
              totalPets: totalPets,
              adoptedPets: adoptedPets,
              availablePets: availablePets,
              dogBreedCount: dogBreedCount,
              catBreedCount: catBreedCount,
            ),
            icon: const Icon(Icons.assessment_outlined, size: 16),
            label: const Text('View Summary Report', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.grey.shade800,
              elevation: 0,
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ] else ...[
          IconButton(
            tooltip: 'View Summary Report',
            icon: const Icon(Icons.assessment_outlined, color: AppTheme.primaryOrange),
            onPressed: () => _showSummaryReportDialog(
              context,
              allPets: allPets,
              totalPets: totalPets,
              adoptedPets: adoptedPets,
              availablePets: availablePets,
              dogBreedCount: dogBreedCount,
              catBreedCount: catBreedCount,
            ),
          ),
          IconButton(
            tooltip: 'Verify Adoption Pass',
            icon: const Icon(Icons.confirmation_number_outlined, color: Color(0xFF3F51B5)),
            onPressed: () => _showQuickPassLookupDialog(context),
          ),
          IconButton(
            tooltip: 'Post a Pet',
            icon: const Icon(Icons.add_circle, color: AppTheme.primaryOrange),
            onPressed: () => AdminAddPetScreen.show(context),
          ),
        ],
      ],
    );
  }

  Widget _buildKpiSection({
    required bool isDesktop,
    required int totalPets,
    required int adoptedPets,
    required int availablePets,
    required String adoptionRate,
    required int totalDogs,
    required int adoptedDogs,
    required int dogBreedCount,
    required int totalCats,
    required int adoptedCats,
    required int catBreedCount,
  }) {
    final cards = [
      _KpiCard(
        title: 'OVERALL ADOPTED',
        value: '$adoptedPets',
        subtitle: '$adoptionRate% overall adoption success',
        badge: 'Top Metric',
        icon: Icons.verified_user_rounded,
        accentColor: const Color(0xFF2E7D32),
        bgColor: const Color(0xFFE8F5E9),
      ),
      _KpiCard(
        title: 'AVAILABLE IN SHELTER',
        value: '$availablePets',
        subtitle: 'Looking for loving homes',
        badge: 'Pending',
        icon: Icons.home_outlined,
        accentColor: const Color(0xFFE65100),
        bgColor: const Color(0xFFFFF3E0),
      ),
      _KpiCard(
        title: 'DOGS & BREEDS',
        value: '$totalDogs Dogs',
        subtitle: '$dogBreedCount unique breeds • $adoptedDogs adopted',
        badge: '🐶 Canines',
        icon: Icons.pets,
        accentColor: const Color(0xFF1565C0),
        bgColor: const Color(0xFFE3F2FD),
      ),
      _KpiCard(
        title: 'CATS & BREEDS',
        value: '$totalCats Cats',
        subtitle: '$catBreedCount unique breeds • $adoptedCats adopted',
        badge: '🐱 Felines',
        icon: Icons.cruelty_free,
        accentColor: const Color(0xFF7B1FA2),
        bgColor: const Color(0xFFF3E5F5),
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: c,
                  ),
                ))
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((c) => SizedBox(
                    width: (constraints.maxWidth - 10) / 2,
                    child: c,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildFilterControls(bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Search box
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search breed name (e.g. Aspin, Shih Tzu, Persian)...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            ),
          ),

          const SizedBox(width: 12),

          // Status filter chips
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusChip('all', 'All Status'),
                _buildStatusChip('available', 'Available'),
                _buildStatusChip('adopted', 'Adopted'),
              ],
            ),
          ),

          if (isDesktop) ...[
            const SizedBox(width: 12),
            // Sort By Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      isDense: true,
                      style: const TextStyle(fontSize: 12.5, color: Colors.black87, fontWeight: FontWeight.w600),
                      items: const [
                        DropdownMenuItem(value: 'count', child: Text('Sort: Highest Count')),
                        DropdownMenuItem(value: 'adopted', child: Text('Sort: Most Adopted')),
                        DropdownMenuItem(value: 'name', child: Text('Sort: Breed Name A-Z')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _sortBy = val);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status, String label) {
    final isSelected = _statusFilter == status;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
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

  Widget _buildBreedGrid({
    required List<_BreedGroup> breeds,
    required String speciesLabel,
    required IconData defaultSpeciesIcon,
    required Color accentColor,
  }) {
    // Filter by search query
    var filtered = breeds.where((b) {
      if (_searchQuery.isEmpty) return true;
      final matchesBreed = b.breedName.toLowerCase().contains(_searchQuery);
      final matchesPet = b.pets.any((p) => p.name.toLowerCase().contains(_searchQuery));
      return matchesBreed || matchesPet;
    }).toList();

    // Filter by status if applied
    if (_statusFilter == 'available') {
      filtered = filtered.where((b) => b.availableCount > 0).toList();
    } else if (_statusFilter == 'adopted') {
      filtered = filtered.where((b) => b.adoptedCount > 0).toList();
    }

    // Sort
    if (_sortBy == 'count') {
      filtered.sort((a, b) => b.totalCount.compareTo(a.totalCount));
    } else if (_sortBy == 'adopted') {
      filtered.sort((a, b) => b.adoptedCount.compareTo(a.adoptedCount));
    } else if (_sortBy == 'name') {
      filtered.sort((a, b) => a.breedName.compareTo(b.breedName));
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(defaultSpeciesIcon, size: 54, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No $speciesLabel breeds match your current filter.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your search query or status filter.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      padding: const EdgeInsets.only(bottom: 24),
      itemBuilder: (context, index) {
        final breedGroup = filtered[index];
        final isExpanded = _expandedBreed == breedGroup.breedName;

        return _buildBreedCard(breedGroup, isExpanded, defaultSpeciesIcon, accentColor);
      },
    );
  }

  Widget _buildBreedCard(
    _BreedGroup breed,
    bool isExpanded,
    IconData defaultSpeciesIcon,
    Color accentColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded ? accentColor.withValues(alpha: 0.5) : Colors.grey.shade200,
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main breed row summary
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _expandedBreed = isExpanded ? null : breed.breedName;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Breed Icon / Avatar
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(defaultSpeciesIcon, color: accentColor, size: 24),
                  ),

                  const SizedBox(width: 16),

                  // Breed Name & Species
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              breed.breedName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            if (breed.breedName.toLowerCase().contains('mixed') ||
                                breed.breedName.toLowerCase().contains('unknown'))
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Text(
                                  'Unspecified / Mixed',
                                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${breed.totalCount} pet${breed.totalCount > 1 ? 's' : ''} registered',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const Text(' • ', style: TextStyle(color: Colors.grey)),
                            Text(
                              '${breed.availableCount} available',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFE65100), fontWeight: FontWeight.w600),
                            ),
                            const Text(' • ', style: TextStyle(color: Colors.grey)),
                            Text(
                              '${breed.adoptedCount} adopted',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Expand Chevron
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),

          // Expanded section: List all pets belonging to this breed
          if (isExpanded) ...[
            const Divider(height: 1),
            Container(
              color: const Color(0xFFFAFBFD),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Registered Pets in "${breed.breedName}" (${breed.pets.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      ),
                      const Spacer(),
                      Text(
                        'Click any pet to view custody/foster info',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: breed.pets.map((pet) => _buildPetChip(pet)).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPetChip(_PetItem pet) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: pet.isAdopted ? const Color(0xFF2E7D32).withValues(alpha: 0.3) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          // Pet Image Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 44,
              color: Colors.grey.shade100,
              child: _buildPetThumbnail(pet.imageUrl),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pet.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: pet.isAdopted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        pet.isAdopted ? 'Adopted' : 'Available',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: pet.isAdopted ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${pet.gender} • ${pet.age.isNotEmpty ? pet.age : "Age unspec."}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (pet.locationAddress.isNotEmpty)
                  Text(
                    '📍 ${pet.locationAddress}',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetThumbnail(String imageUrl) {
    if (imageUrl.startsWith('data:image')) {
      try {
        final base64Str = imageUrl.split(',').last;
        return Image.memory(
          base64Decode(base64Str),
          fit: BoxFit.cover,
          cacheWidth: 160,
          cacheHeight: 160,
        );
      } catch (_) {}
    } else if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 20, color: Colors.grey),
      );
    }
    return const Icon(Icons.pets, size: 20, color: Colors.grey);
  }

  List<_BreedGroup> _groupBreeds(List<_PetItem> pets) {
    final Map<String, List<_PetItem>> map = {};
    for (final pet in pets) {
      final normalized = pet.breed.trim().isEmpty ? 'Mixed / Unknown' : pet.breed.trim();
      map.putIfAbsent(normalized, () => []).add(pet);
    }

    return map.entries.map((entry) {
      final total = entry.value.length;
      final adopted = entry.value.where((p) => p.isAdopted).length;
      return _BreedGroup(
        breedName: entry.key,
        totalCount: total,
        adoptedCount: adopted,
        availableCount: total - adopted,
        pets: entry.value,
      );
    }).toList();
  }

  void _showSummaryReportDialog(
    BuildContext context, {
    required List<_PetItem> allPets,
    required int totalPets,
    required int adoptedPets,
    required int availablePets,
    required int dogBreedCount,
    required int catBreedCount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _SummaryReportDialog(
        allPets: allPets,
        totalPets: totalPets,
        adoptedPets: adoptedPets,
        availablePets: availablePets,
        dogBreedCount: dogBreedCount,
        catBreedCount: catBreedCount,
      ),
    );
  }

  // ─── Center Handover Verification & Quick Pass Lookup ───────────────────────

  Widget _buildPetThumb(String imageUrl, String petId) {
    if (imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.pets, color: Colors.grey, size: 24),
      );
    }
    if (imageUrl.startsWith('data:image')) {
      try {
        final commaIdx = imageUrl.indexOf(',');
        final base64Str = commaIdx != -1 ? imageUrl.substring(commaIdx + 1) : imageUrl;
        final bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {
        return Container(color: Colors.grey.shade200, child: const Icon(Icons.pets, color: Colors.grey));
      }
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.pets, color: Colors.grey)),
    );
  }

  Widget _buildInquiryStatusBadge(String status) {
    final s = status.toLowerCase();
    Color bg;
    Color fg;
    String label;

    if (s == 'completed') {
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
      label = 'Claimed';
    } else if (s == 'scheduled') {
      bg = const Color(0xFF3F51B5).withValues(alpha: 0.12);
      fg = const Color(0xFF3F51B5);
      label = 'Scheduled Pickup 📅';
    } else {
      bg = Colors.amber.shade50;
      fg = Colors.amber.shade900;
      label = 'Pending Discussion';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Future<void> _showQuickPassLookupDialog(BuildContext context) async {
    final codeController = TextEditingController();
    bool isSearching = false;
    String? errorMessage;
    Map<String, dynamic>? foundInquiry;
    String? foundInquiryId;

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
                  child: const Icon(Icons.confirmation_number_rounded, color: Color(0xFF3F51B5), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Verify Adoption Pass',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'When an adopter arrives to retrieve their pet, enter their 5-character Adoption Pass or check the scheduled pickups below.',
                      style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: codeController,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 5,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                            ),
                            decoration: InputDecoration(
                              hintText: 'e.g. K9B7X',
                              hintStyle: TextStyle(letterSpacing: 2, color: Colors.grey.shade400),
                              counterText: '',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: isSearching
                              ? null
                              : () async {
                                  final code = codeController.text.trim().toUpperCase();
                                  if (code.length < 5) {
                                    setDialogState(() {
                                      errorMessage = 'Please enter a valid 5-character ID';
                                      foundInquiry = null;
                                      foundInquiryId = null;
                                    });
                                    return;
                                  }

                                  setDialogState(() {
                                    isSearching = true;
                                    errorMessage = null;
                                    foundInquiry = null;
                                    foundInquiryId = null;
                                  });

                                  try {
                                    final snap = await FirebaseDatabase.instance
                                        .ref()
                                        .child('adoption_inquiries')
                                        .orderByChild('adoptionCode')
                                        .equalTo(code)
                                        .get();

                                    if (snap.exists && snap.value is Map) {
                                      final map = snap.value as Map;
                                      final entry = map.entries.first;
                                      setDialogState(() {
                                        foundInquiryId = entry.key.toString();
                                        foundInquiry = Map<String, dynamic>.from(entry.value as Map);
                                        isSearching = false;
                                      });
                                    } else {
                                      setDialogState(() {
                                        errorMessage = 'No active adoption pass found for "$code".';
                                        isSearching = false;
                                      });
                                    }
                                  } catch (e) {
                                    setDialogState(() {
                                      errorMessage = 'Lookup failed: $e';
                                      isSearching = false;
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3F51B5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: isSearching
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Lookup Pass', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (foundInquiry != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: _buildPetThumb(
                                      foundInquiry!['petImageUrl']?.toString() ?? '',
                                      foundInquiry!['petId']?.toString() ?? '',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        foundInquiry!['petName']?.toString() ?? 'Rescued Pet',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      Text(
                                        '${foundInquiry!['petBreed'] ?? ''} • ${foundInquiry!['petCategory'] ?? 'Pet'}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Foster: ${foundInquiry!['fosterName'] ?? 'Foster Care'}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildInquiryStatusBadge(foundInquiry!['status']?.toString() ?? 'pending'),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                const Icon(Icons.person, size: 14, color: AppTheme.primaryOrange),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('Adopter: ${foundInquiry!['adopterName'] ?? 'Adopter'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            if (foundInquiry!['scheduledPickupDate'] != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3F51B5).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.event, size: 14, color: Color(0xFF3F51B5)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Scheduled Retrieval: ${foundInquiry!['scheduledPickupDate']}',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (foundInquiry!['adopterPhone'] != null && foundInquiry!['adopterPhone'].toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.phone, size: 14, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  Text('Phone: ${foundInquiry!['adopterPhone']}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            if (foundInquiry!['adopterAgreedTerms'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.green.shade300),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified, size: 14, color: Colors.green),
                                    SizedBox(width: 4),
                                    Text(
                                      'Terms & Pre-Screening Agreed by Adopter',
                                      style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 14),
                            if ((foundInquiry!['status']?.toString().toLowerCase()) != 'completed') ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _showCenterHandoverDialog(context, foundInquiryId!, foundInquiry!);
                                  },
                                  icon: const Icon(Icons.check_circle, size: 16),
                                  label: const Text('Mark as Claimed / Handover Complete', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ] else ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.verified, color: Colors.green, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Handover Completed • Pet Adopted',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade900),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Scheduled Pickups List
                    const Text(
                      'Scheduled Pickups Awaiting Retrieval:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<DatabaseEvent>(
                      stream: FirebaseDatabase.instance.ref().child('adoption_inquiries').onValue,
                      builder: (context, inqSnap) {
                        if (!inqSnap.hasData || inqSnap.data?.snapshot.value == null) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No pending retrieval passes.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          );
                        }

                        final map = inqSnap.data!.snapshot.value as Map;
                        final scheduled = <Map<String, dynamic>>[];
                        map.forEach((k, v) {
                          if (v is Map) {
                            final inq = Map<String, dynamic>.from(v);
                            inq['inquiryId'] = k.toString();
                            final st = (inq['status'] ?? '').toString().toLowerCase();
                            final bool retrieved = inq['petRetrieved'] == true || inq['isHandedOver'] == true;
                            if (st != 'completed' && !retrieved && (st == 'scheduled' || inq['adopterAgreedTerms'] == true || inq['adoptionCode'] != null)) {
                              scheduled.add(inq);
                            }
                          }
                        });

                        if (scheduled.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No scheduled pickups awaiting retrieval right now.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          );
                        }

                        return Column(
                          children: scheduled.map((inq) {
                            final code = inq['adoptionCode']?.toString() ?? 'Pass';
                            final petName = inq['petName']?.toString() ?? 'Pet';
                            final adopterName = inq['adopterName']?.toString() ?? 'Adopter';
                            final pickup = inq['scheduledPickupDate']?.toString() ?? 'Date to be agreed';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3F51B5).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      code,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Color(0xFF3F51B5)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('$petName • Adopter: $adopterName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text('Pickup: $pickup', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _showCenterHandoverDialog(context, inq['inquiryId'], inq);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade600,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    child: const Text('Mark Claimed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

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
    final scheduledPickupDate = data['scheduledPickupDate']?.toString();
    final expectedCode = (data['adoptionCode']?.toString() ?? '').toUpperCase().trim();

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
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F51B5).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified, color: Color(0xFF3F51B5), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Mark Pet as Retrieved',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm that $adopterName has claimed $petName at the Adoption Center to finalize the adoption handover.',
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
                    if (scheduledPickupDate != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3F51B5).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF3F51B5).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available, color: Color(0xFF3F51B5), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Scheduled Retrieval Date: $scheduledPickupDate',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                            'ADOPTION PASS CODE',
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
                              'body': 'Your adoption of $petName was verified and marked as retrieved at the center. Congratulations!',
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

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Handover confirmed! $petName marked as claimed by $adopterName.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to confirm handover: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm Pet Retrieved', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

class _PetItem {
  final String id;
  final String name;
  final String breed;
  final String category;
  final bool isAdopted;
  final String gender;
  final String age;
  final String imageUrl;
  final String fosterId;
  final String locationAddress;
  final int createdAt;
  final int adoptedAt;
  final bool isVaccinated;
  final bool isDewormed;
  final bool isMicrochipped;
  final bool isNeutered;

  _PetItem({
    required this.id,
    required this.name,
    required this.breed,
    required this.category,
    required this.isAdopted,
    required this.gender,
    required this.age,
    required this.imageUrl,
    required this.fosterId,
    required this.locationAddress,
    this.createdAt = 0,
    this.adoptedAt = 0,
    this.isVaccinated = false,
    this.isDewormed = false,
    this.isMicrochipped = false,
    this.isNeutered = false,
  });

  factory _PetItem.fromMap(String id, Map data) {
    int parseTs(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    final isAdopted = data['isAdopted'] == true ||
        (data['status'] ?? '').toString().toLowerCase() == 'adopted' ||
        (data['status'] ?? '').toString().toLowerCase() == 'completed';

    return _PetItem(
      id: id,
      name: (data['name'] ?? 'Pet').toString(),
      breed: (data['breed'] ?? 'Mixed / Unknown').toString(),
      category: (data['category'] ?? 'Dogs').toString(),
      isAdopted: isAdopted,
      gender: (data['gender'] ?? 'Unknown').toString(),
      age: (data['age'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      fosterId: (data['fosterId'] ?? '').toString(),
      locationAddress: (data['locationAddress'] ?? '').toString(),
      createdAt: parseTs(data['createdAt']),
      adoptedAt: parseTs(data['adoptedAt'] ?? data['completedAt']),
      isVaccinated: data['isVaccinated'] == true || data['vaccine'] == true,
      isDewormed: data['isDewormed'] == true || data['dewormed'] == true,
      isMicrochipped: data['isMicrochipped'] == true || data['microchip'] == true,
      isNeutered: data['isNeutered'] == true || data['neutered'] == true,
    );
  }
}

class _BreedGroup {
  final String breedName;
  final int totalCount;
  final int adoptedCount;
  final int availableCount;
  final List<_PetItem> pets;

  _BreedGroup({
    required this.breedName,
    required this.totalCount,
    required this.adoptedCount,
    required this.availableCount,
    required this.pets,
  });
}

// ─── KPI Card Widget ─────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color accentColor;
  final Color bgColor;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accentColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Summary Report Dialog (Day, Week, Month, All-Time) ─────────────────────

class _SummaryReportDialog extends StatefulWidget {
  final List<_PetItem> allPets;
  final int totalPets;
  final int adoptedPets;
  final int availablePets;
  final int dogBreedCount;
  final int catBreedCount;

  const _SummaryReportDialog({
    required this.allPets,
    required this.totalPets,
    required this.adoptedPets,
    required this.availablePets,
    required this.dogBreedCount,
    required this.catBreedCount,
  });

  @override
  State<_SummaryReportDialog> createState() => _SummaryReportDialogState();
}

class _SummaryReportDialogState extends State<_SummaryReportDialog> {
  String _selectedTimeframe = 'day'; // 'day' (Current Day), 'week' (This Week), 'month' (This Month), 'all' (All Time)

  DateTime get _now => DateTime.now();

  String get _timeframeLabel {
    switch (_selectedTimeframe) {
      case 'day':
        return 'Current Day';
      case 'week':
        return 'This Week';
      case 'month':
        return 'This Month';
      case 'all':
      default:
        return 'All Time';
    }
  }

  String get _dateRangeStr {
    final now = _now;
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    if (_selectedTimeframe == 'day') {
      return '${weekdays[now.weekday - 1]}, ${monthNames[now.month - 1]} ${now.day}, ${now.year}';
    } else if (_selectedTimeframe == 'week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      return '${shortMonths[monday.month - 1]} ${monday.day} – ${shortMonths[now.month - 1]} ${now.day}, ${now.year}';
    } else if (_selectedTimeframe == 'month') {
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      return '${monthNames[now.month - 1]} 1 – $lastDay, ${now.year}';
    } else {
      return 'Cumulative Historical Records';
    }
  }

  DateTime get _startTime {
    final now = _now;
    if (_selectedTimeframe == 'day') {
      return DateTime(now.year, now.month, now.day);
    } else if (_selectedTimeframe == 'week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      return DateTime(monday.year, monday.month, monday.day);
    } else if (_selectedTimeframe == 'month') {
      return DateTime(now.year, now.month, 1);
    } else {
      return DateTime(2020);
    }
  }

  DateTime get _endTime {
    final now = _now;
    if (_selectedTimeframe == 'day') {
      return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (_selectedTimeframe == 'week') {
      return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (_selectedTimeframe == 'month') {
      return DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    } else {
      return DateTime(2100);
    }
  }

  List<_PetItem> _getPetsInPeriod() {
    if (_selectedTimeframe == 'all') return widget.allPets;
    final startMs = _startTime.millisecondsSinceEpoch;
    final endMs = _endTime.millisecondsSinceEpoch;
    return widget.allPets.where((p) {
      if (p.createdAt > 0) {
        return p.createdAt >= startMs && p.createdAt <= endMs;
      }
      return false;
    }).toList();
  }

  List<_PetItem> _getAdoptedInPeriod() {
    if (_selectedTimeframe == 'all') {
      return widget.allPets.where((p) => p.isAdopted).toList();
    }
    final startMs = _startTime.millisecondsSinceEpoch;
    final endMs = _endTime.millisecondsSinceEpoch;
    return widget.allPets.where((p) {
      if (!p.isAdopted) return false;
      if (p.adoptedAt > 0) {
        return p.adoptedAt >= startMs && p.adoptedAt <= endMs;
      }
      if (p.createdAt > 0) {
        return p.createdAt >= startMs && p.createdAt <= endMs;
      }
      return false;
    }).toList();
  }

  void _copySummary(
    BuildContext context, {
    required int listed,
    required int adopted,
    required int inquiries,
    required int scheduled,
    required int dogsListed,
    required int catsListed,
    required int otherListed,
    required int dogsAdopted,
    required int catsAdopted,
    required List<String> topBreeds,
  }) {
    final report = StringBuffer();
    report.writeln('🐾 SAVE-A-PAWS: SUMMARY REPORT (${_timeframeLabel.toUpperCase()})');
    report.writeln('====================================================');
    report.writeln('Timeframe: $_timeframeLabel');
    report.writeln('Date Range: $_dateRangeStr');
    report.writeln('Generated on: ${DateTime.now().toLocal().toString().split('.').first}');
    report.writeln('----------------------------------------------------');
    report.writeln('📊 KEY METRICS');
    report.writeln('• New Pets Listed: $listed');
    report.writeln('• Adoptions Completed: $adopted');
    report.writeln('• Inquiries Received: $inquiries');
    report.writeln('• Scheduled Handover Pickups: $scheduled');
    report.writeln('• Center Catalog Inventory: ${widget.availablePets} pets ready for adoption');
    report.writeln('----------------------------------------------------');
    report.writeln('🐶🐱 SPECIES BREAKDOWN (THIS PERIOD)');
    report.writeln('• Dogs: $dogsListed listed, $dogsAdopted adopted');
    report.writeln('• Cats: $catsListed listed, $catsAdopted adopted');
    if (otherListed > 0) {
      report.writeln('• Other Animals: $otherListed listed');
    }
    if (topBreeds.isNotEmpty) {
      report.writeln('----------------------------------------------------');
      report.writeln('🏷️ ACTIVE BREEDS (THIS PERIOD)');
      for (final b in topBreeds) {
        report.writeln('• $b');
      }
    }
    report.writeln('====================================================');

    Clipboard.setData(ClipboardData(text: report.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$_timeframeLabel summary report copied to clipboard!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildTimeframeTab(String key, String title, IconData icon) {
    final bool isSelected = _selectedTimeframe == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTimeframe = key),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primaryOrange : Colors.grey.shade300,
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryOrange.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSpeciesRow(String species, String listed, String adopted) {
    return Row(
      children: [
        Text(species, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
          child: Text(listed, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
          child: Text(adopted, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
        ),
      ],
    );
  }

  Widget _buildSnapshotRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 680;

    final petsInPeriod = _getPetsInPeriod();
    final adoptedInPeriod = _getAdoptedInPeriod();

    final dogsListed = petsInPeriod.where((p) => p.category.toLowerCase() == 'dogs').length;
    final catsListed = petsInPeriod.where((p) => p.category.toLowerCase() == 'cats').length;
    final otherListed = petsInPeriod.where((p) => p.category.toLowerCase() != 'dogs' && p.category.toLowerCase() != 'cats').length;

    final dogsAdopted = adoptedInPeriod.where((p) => p.category.toLowerCase() == 'dogs').length;
    final catsAdopted = adoptedInPeriod.where((p) => p.category.toLowerCase() == 'cats').length;

    // Breed frequency in period
    final Map<String, int> breedCounts = {};
    for (final p in petsInPeriod) {
      breedCounts[p.breed] = (breedCounts[p.breed] ?? 0) + 1;
    }
    final sortedBreeds = breedCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topBreedStrings = sortedBreeds.take(5).map((e) => '${e.key} (${e.value})').toList();

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('adoption_inquiries').onValue,
      builder: (context, inqSnap) {
        final allInquiries = <Map<String, dynamic>>[];
        if (inqSnap.hasData && inqSnap.data?.snapshot.value is Map) {
          final map = inqSnap.data!.snapshot.value as Map;
          map.forEach((k, v) {
            if (v is Map) {
              final inq = Map<String, dynamic>.from(v);
              inq['inquiryId'] = k.toString();
              allInquiries.add(inq);
            }
          });
        }

        final startMs = _startTime.millisecondsSinceEpoch;
        final endMs = _endTime.millisecondsSinceEpoch;

        final inquiriesInPeriod = allInquiries.where((inq) {
          if (_selectedTimeframe == 'all') return true;
          final ts = inq['timestamp'];
          final tsNum = ts is num ? ts.toInt() : (ts is String ? int.tryParse(ts) ?? 0 : 0);
          if (tsNum > 0) {
            return tsNum >= startMs && tsNum <= endMs;
          }
          return false;
        }).toList();

        final scheduledInPeriod = allInquiries.where((inq) {
          final st = (inq['status'] ?? '').toString().toLowerCase();
          final bool retrieved = inq['petRetrieved'] == true || inq['isHandedOver'] == true;
          if (st == 'completed' || retrieved) return false;
          if (st == 'scheduled' || inq['adopterAgreedTerms'] == true || inq['adoptionCode'] != null) {
            if (_selectedTimeframe == 'all') return true;
            final ts = inq['timestamp'];
            final tsNum = ts is num ? ts.toInt() : (ts is String ? int.tryParse(ts) ?? 0 : 0);
            return tsNum >= startMs && tsNum <= endMs;
          }
          return false;
        }).toList();

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780, maxHeight: 840),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.assessment_outlined, color: AppTheme.primaryOrange, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Adoption & Breed Summary Report',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Filter performance by current day, week, month, or cumulative history',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Scrollable Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timeframe Switcher Tabs
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              _buildTimeframeTab('day', 'Current Day', Icons.today),
                              const SizedBox(width: 4),
                              _buildTimeframeTab('week', 'This Week', Icons.date_range),
                              const SizedBox(width: 4),
                              _buildTimeframeTab('month', 'This Month', Icons.calendar_month),
                              const SizedBox(width: 4),
                              _buildTimeframeTab('all', 'All Time', Icons.all_inclusive),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Date Range Banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4F8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFD9E2EC)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event, size: 18, color: Color(0xFF334E68)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Reporting Period: $_dateRangeStr',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF102A43),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryOrange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _timeframeLabel,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryOrange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // 4 KPI Cards Grid
                        isCompact
                            ? Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildMetricTile(
                                          title: 'Pets Listed',
                                          value: '${petsInPeriod.length}',
                                          subtitle: 'New catalog entries',
                                          icon: Icons.add_business_outlined,
                                          color: AppTheme.primaryOrange,
                                          bg: const Color(0xFFFFF3E0),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildMetricTile(
                                          title: 'Pets Adopted',
                                          value: '${adoptedInPeriod.length}',
                                          subtitle: 'Successfully placed',
                                          icon: Icons.verified_user_rounded,
                                          color: const Color(0xFF2E7D32),
                                          bg: const Color(0xFFE8F5E9),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildMetricTile(
                                          title: 'Applications',
                                          value: '${inquiriesInPeriod.length}',
                                          subtitle: 'Inquiries received',
                                          icon: Icons.assignment_outlined,
                                          color: const Color(0xFF1976D2),
                                          bg: const Color(0xFFE3F2FD),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildMetricTile(
                                          title: 'Scheduled',
                                          value: '${scheduledInPeriod.length}',
                                          subtitle: 'Awaiting retrieval',
                                          icon: Icons.calendar_month_rounded,
                                          color: const Color(0xFF6A1B9A),
                                          bg: const Color(0xFFF3E5F5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: _buildMetricTile(
                                      title: 'Pets Listed',
                                      value: '${petsInPeriod.length}',
                                      subtitle: 'New catalog entries',
                                      icon: Icons.add_business_outlined,
                                      color: AppTheme.primaryOrange,
                                      bg: const Color(0xFFFFF3E0),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildMetricTile(
                                      title: 'Pets Adopted',
                                      value: '${adoptedInPeriod.length}',
                                      subtitle: 'Successfully placed',
                                      icon: Icons.verified_user_rounded,
                                      color: const Color(0xFF2E7D32),
                                      bg: const Color(0xFFE8F5E9),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildMetricTile(
                                      title: 'Applications',
                                      value: '${inquiriesInPeriod.length}',
                                      subtitle: 'Inquiries received',
                                      icon: Icons.assignment_outlined,
                                      color: const Color(0xFF1976D2),
                                      bg: const Color(0xFFE3F2FD),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildMetricTile(
                                      title: 'Scheduled',
                                      value: '${scheduledInPeriod.length}',
                                      subtitle: 'Awaiting retrieval',
                                      icon: Icons.calendar_month_rounded,
                                      color: const Color(0xFF6A1B9A),
                                      bg: const Color(0xFFF3E5F5),
                                    ),
                                  ),
                                ],
                              ),

                        const SizedBox(height: 18),

                        // Section 2: Species Breakdown & Catalog Snapshot
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.pets, size: 16, color: AppTheme.primaryOrange),
                                        SizedBox(width: 6),
                                        Text(
                                          'Species Activity (This Period)',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _buildSpeciesRow('🐶 Dogs', '$dogsListed listed', '$dogsAdopted adopted'),
                                    const Divider(height: 16),
                                    _buildSpeciesRow('🐱 Cats', '$catsListed listed', '$catsAdopted adopted'),
                                    if (otherListed > 0) ...[
                                      const Divider(height: 16),
                                      _buildSpeciesRow('🐾 Others', '$otherListed listed', '0 adopted'),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.warehouse_outlined, size: 16, color: Color(0xFF3F51B5)),
                                        SizedBox(width: 6),
                                        Text(
                                          'Center Catalog Snapshot',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _buildSnapshotRow('Available Inventory', '${widget.availablePets} pets ready for adoption'),
                                    const Divider(height: 16),
                                    _buildSnapshotRow('Overall Placed', '${widget.adoptedPets} pets happily adopted'),
                                    const Divider(height: 16),
                                    _buildSnapshotRow('Breeds Documented', '${widget.dogBreedCount} dog & ${widget.catBreedCount} cat breeds'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // Section 3: Recent Activity / Documented Breeds in Timeframe
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.history_toggle_off, size: 16, color: Colors.black87),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Period Highlights: $_timeframeLabel',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${petsInPeriod.length} pets • ${inquiriesInPeriod.length} inquiries',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (petsInPeriod.isEmpty && inquiriesInPeriod.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  alignment: Alignment.center,
                                  child: Column(
                                    children: [
                                      Icon(Icons.inbox_outlined, size: 36, color: Colors.grey.shade400),
                                      const SizedBox(height: 6),
                                      Text(
                                        'No pet listings or applications logged specifically for $_timeframeLabel yet.',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Shelter inventory remains active with ${widget.availablePets} pets ready for adoption.',
                                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                if (topBreedStrings.isNotEmpty) ...[
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: topBreedStrings.map((b) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Text(
                                          b,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Column(
                                  children: petsInPeriod.take(4).map((pet) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            pet.category.toLowerCase() == 'cats' ? Icons.cruelty_free : Icons.pets,
                                            size: 16,
                                            color: AppTheme.primaryOrange,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${pet.name} (${pet.breed})',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: pet.isAdopted ? Colors.green.shade50 : Colors.amber.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              pet.isAdopted ? 'Adopted' : 'Available',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: pet.isAdopted ? Colors.green.shade800 : Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Footer Actions
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _copySummary(
                          context,
                          listed: petsInPeriod.length,
                          adopted: adoptedInPeriod.length,
                          inquiries: inquiriesInPeriod.length,
                          scheduled: scheduledInPeriod.length,
                          dogsListed: dogsListed,
                          catsListed: catsListed,
                          otherListed: otherListed,
                          dogsAdopted: dogsAdopted,
                          catsAdopted: catsAdopted,
                          topBreeds: topBreedStrings,
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text('Copy $_timeframeLabel Report', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Close', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
}

