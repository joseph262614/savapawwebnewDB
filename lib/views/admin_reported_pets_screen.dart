import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_map_dialog.dart';
import '../widgets/app_optimized_image.dart';
import 'admin_screen.dart';
import 'admin_report_pet_screen.dart';

class AdminReportedPetsScreen extends StatefulWidget {
  final bool embeddedMode;

  const AdminReportedPetsScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminReportedPetsScreen> createState() => _AdminReportedPetsScreenState();
}

class _AdminReportedPetsScreenState extends State<AdminReportedPetsScreen> {
  bool _isMapView = false;
  final MapController _mapController = MapController();
  Map<String, dynamic>? _selectedReportForMap;
  String _selectedFilter = 'all'; // 'all', 'open', 'in progress', 'rescued', 'closed'
  String _selectedTypeFilter = 'all'; // 'all', 'stray', 'missing'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      int millis = 0;
      if (timestamp is int) {
        millis = timestamp;
      } else if (timestamp is num) {
        millis = timestamp.toInt();
      } else if (timestamp is String) {
        millis = int.tryParse(timestamp) ?? 0;
      }
      if (millis == 0) return 'Recent';
      final dt = DateTime.fromMillisecondsSinceEpoch(millis);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $ampm';
    } catch (_) {
      return 'Recent';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.redAccent;
      case 'in progress':
      case 'responding':
        return Colors.blue;
      case 'rescued':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return AppTheme.primaryOrange;
    }
  }

  Widget _buildPetThumbnail(String? imageUrl, {double size = 56}) {
    return AppOptimizedImage(
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: size > 200 ? 800 : 200,
      cacheHeight: size > 200 ? 800 : 200,
      borderRadius: BorderRadius.circular(10),
    );
  }

  void _showImageDialog(BuildContext context, String? imageUrl, String title) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildPetThumbnail(imageUrl, size: 400),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(String reportKey, String newStatus) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final updates = <String, dynamic>{
        'status': newStatus,
        'updatedAt': ServerValue.timestamp,
        'lastUpdatedBy': user?.uid ?? 'admin',
        'lastUpdatedByEmail': user?.email ?? 'admin',
      };
      if (newStatus == 'In Progress') {
        updates['responderName'] = 'Admin / Coordinator';
        updates['respondedAt'] = ServerValue.timestamp;
      } else if (newStatus == 'Rescued') {
        updates['rescuedAt'] = ServerValue.timestamp;
      }
      await FirebaseDatabase.instance.ref().child('reports').child(reportKey).update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report marked as $newStatus'),
            backgroundColor: AppTheme.primaryTeal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _confirmDeleteReport(BuildContext context, String reportKey, String petType) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: Text('Are you sure you want to permanently delete this report for $petType? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              try {
                await FirebaseDatabase.instance.ref().child('reports').child(reportKey).remove();
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Report deleted successfully'), backgroundColor: Colors.redAccent),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Error deleting report: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showReportDetailsDialog(BuildContext context, Map<String, dynamic> report) {
    final reportKey = report['reportKey'] ?? report['id'] ?? '';
    final petType = report['petType'] ?? 'Animal';
    final desc = report['description'] ?? 'No description provided';
    final address = report['address'] ?? 'No address';
    final status = report['status'] ?? 'Open';
    final imageUrl = report['imageUrl']?.toString();
    final timeStr = _formatDate(report['timestamp']);
    final lat = report['lat'];
    final lng = report['lng'];
    double? parsedLat;
    double? parsedLng;
    if (lat is num) parsedLat = lat.toDouble();
    if (lng is num) parsedLng = lng.toDouble();
    if (parsedLat == null && lat is String) parsedLat = double.tryParse(lat);
    if (parsedLng == null && lng is String) parsedLng = double.tryParse(lng);
    final hasValidCoordinates = parsedLat != null && parsedLng != null;
    final petCoordinates = hasValidCoordinates ? LatLng(parsedLat, parsedLng) : const LatLng(14.5320, 121.0781);

    final responderName = report['responderName'];
    final userId = report['userId'];
    final bool isMissing = (report['reportType'] == 'missing') || (report['isMissingPet'] == true);
    final String? petName = report['petName']?.toString();
    final String? contactPhone = report['contactPhone']?.toString();
    final String? rescuedImageUrl = report['rescuedImageUrl']?.toString();
    final String? rescueNotes = report['rescueNotes']?.toString();
    final String? rescuerName = report['rescuerName']?.toString();
    final String? rescuedDate = report['rescuedDate']?.toString();
    final String? rescuedTime = report['rescuedTime']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isMissing ? const Color(0xFFC62828) : _getStatusColor(status)).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isMissing ? Icons.person_search_rounded : Icons.pets,
                color: isMissing ? const Color(0xFFC62828) : _getStatusColor(status),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isMissing ? 'Missing Pet Report: ${petName ?? petType}' : '$petType Report Details',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMissing) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFCDD2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Missing Pet: ${petName ?? 'Unknown'}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFB71C1C)),
                              ),
                              if (contactPhone != null && contactPhone.isNotEmpty)
                                Text(
                                  'Owner Contact Phone: $contactPhone',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _showImageDialog(context, imageUrl, petType),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildPetThumbnail(imageUrl, size: 220),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (rescuedImageUrl != null && rescuedImageUrl.isNotEmpty) ...[
                  const Text('Rescue Verification Proof (Live Photo):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showImageDialog(context, rescuedImageUrl, 'Rescue Proof: $petType'),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildPetThumbnail(rescuedImageUrl, size: 220),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildInfoRow('Report Type', isMissing ? 'Missing Pet Alert' : 'Stray Animal Report'),
                if (isMissing && petName != null) _buildInfoRow('Pet Name', petName),
                if (isMissing && contactPhone != null) _buildInfoRow('Owner Phone', contactPhone),
                _buildInfoRow('Report ID', reportKey),
                _buildInfoRow('Animal Type', petType),
                _buildInfoRow('Status', status),
                if (status == 'Rescued') ...[
                  if (rescuerName != null) _buildInfoRow('Rescued By', rescuerName),
                  if (rescuedDate != null || rescuedTime != null)
                    _buildInfoRow('Rescued At', '${rescuedDate ?? ''} ${rescuedTime ?? ''}'.trim()),
                  if (rescueNotes != null && rescueNotes.isNotEmpty)
                    _buildInfoRow('Rescue Notes', rescueNotes),
                ],
                _buildInfoRow('Reported At', timeStr),
                _buildInfoRow('Reporter UID', userId?.toString() ?? 'N/A'),
                if (responderName != null) _buildInfoRow('Responder', responderName.toString()),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Location & Address:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    TextButton.icon(
                      onPressed: () {
                        AdminMapDialog.showLocation(
                          context,
                          location: petCoordinates,
                          title: isMissing ? 'Last Seen: ${petName ?? petType}' : 'Reported Stray: $petType',
                          landmark: address,
                        );
                      },
                      icon: const Icon(Icons.map_rounded, size: 14, color: AppTheme.primaryOrange),
                      label: const Text('Open Maps', style: TextStyle(color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(address, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                if (parsedLat != null && parsedLng != null) ...[
                  const SizedBox(height: 4),
                  Text('GPS: ${parsedLat.toStringAsFixed(4)}, ${parsedLng.toStringAsFixed(4)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
                const SizedBox(height: 8),
                // Embedded Map preview (matching Photo 1)
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: petCoordinates,
                          initialZoom: 15,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'org.saveapaws.admin',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: petCoordinates,
                                width: 40,
                                height: 40,
                                alignment: Alignment.topCenter,
                                child: const Icon(Icons.location_on, color: AppTheme.primaryOrange, size: 36),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: FloatingActionButton.small(
                          heroTag: 'dialog_map_$reportKey',
                          onPressed: () {
                            AdminMapDialog.showLocation(
                              context,
                              location: petCoordinates,
                              title: isMissing ? 'Last Seen: ${petName ?? petType}' : 'Reported Stray: $petType',
                              landmark: address,
                            );
                          },
                          tooltip: 'Expand Map / Open Maps',
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.fullscreen, color: AppTheme.primaryOrange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Description & Condition:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(desc, style: const TextStyle(fontSize: 13, height: 1.4)),
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
          if (status == 'Rescued')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, size: 16, color: Colors.green),
                  SizedBox(width: 6),
                  Text('Rescue Verified (Locked)', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Change Status',
              onSelected: (val) {
                Navigator.pop(ctx);
                _updateStatus(reportKey, val);
              },
              itemBuilder: (c) => [
                const PopupMenuItem(value: 'Open', child: Text('Mark as Open (Needs Help)')),
                const PopupMenuItem(value: 'In Progress', child: Text('Mark as In Progress')),
                const PopupMenuItem(value: 'Rescued', child: Text('Mark as Rescued')),
                const PopupMenuItem(value: 'Closed', child: Text('Mark as Closed')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Update Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('reports').onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange));
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

        final missingCount = allReports.where((r) => (r['reportType'] == 'missing') || (r['isMissingPet'] == true)).length;
        final strayCount = allReports.length - missingCount;
        final openCount = allReports.where((r) => (r['status'] ?? 'Open').toString().toLowerCase() == 'open').length;
        final inProgressCount = allReports.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'in progress').length;
        final rescuedCount = allReports.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'rescued').length;
        final closedCount = allReports.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'closed').length;

        // Filter
        List<Map<String, dynamic>> filtered = allReports;
        if (_selectedTypeFilter == 'missing') {
          filtered = filtered.where((r) => (r['reportType'] == 'missing') || (r['isMissingPet'] == true)).toList();
        } else if (_selectedTypeFilter == 'stray') {
          filtered = filtered.where((r) => (r['reportType'] != 'missing') && (r['isMissingPet'] != true)).toList();
        }

        if (_selectedFilter != 'all') {
          filtered = filtered.where((r) => (r['status'] ?? 'Open').toString().toLowerCase() == _selectedFilter).toList();
        }

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filtered = filtered.where((r) {
            final type = (r['petType'] ?? '').toString().toLowerCase();
            final desc = (r['description'] ?? '').toString().toLowerCase();
            final addr = (r['address'] ?? '').toString().toLowerCase();
            final id = (r['reportKey'] ?? '').toString().toLowerCase();
            final name = (r['petName'] ?? '').toString().toLowerCase();
            final phone = (r['contactPhone'] ?? '').toString().toLowerCase();
            return type.contains(q) || desc.contains(q) || addr.contains(q) || id.contains(q) || name.contains(q) || phone.contains(q);
          }).toList();
        }

        return Container(
          color: const Color(0xFFF5F5F8),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.emergency, color: Colors.redAccent, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reported Pets in Need (Rescue Hub)',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Real-time emergency reports, location data, and rescue dispatch.',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _isMapView = !_isMapView),
                          icon: Icon(_isMapView ? Icons.view_list_rounded : Icons.map_rounded, size: 16),
                          label: Text(
                            _isMapView ? 'Switch to List View' : 'Live Incident Map',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryOrange,
                            side: const BorderSide(color: AppTheme.primaryOrange, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => AdminReportPetScreen.show(context),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Report a Pet / Missing Pet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Stats Cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = isDesktop ? (constraints.maxWidth - 64) / 5 : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildStatCard('Total Reports', '${allReports.length}', Icons.pets, AppTheme.primaryOrange, itemWidth),
                        _buildStatCard('Missing Pets', '$missingCount', Icons.person_search_rounded, const Color(0xFFC62828), itemWidth),
                        _buildStatCard('Needs Help (Open)', '$openCount', Icons.emergency, Colors.redAccent, itemWidth),
                        _buildStatCard('Responding', '$inProgressCount', Icons.directions_run, Colors.blue, itemWidth),
                        _buildStatCard('Rescued', '$rescuedCount', Icons.check_circle, Colors.green, itemWidth),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),

                // Controls: Search & Filter Tabs
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) => setState(() => _searchQuery = val.trim()),
                              decoration: InputDecoration(
                                hintText: 'Search by animal, pet name, location, owner phone, or report ID...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Row 1: Type Selection (All vs Stray vs Missing)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildTypeFilterTab('all', 'All Reports (${allReports.length})'),
                            const SizedBox(width: 8),
                            _buildTypeFilterTab('stray', 'Stray Animals ($strayCount)', color: AppTheme.primaryOrange),
                            const SizedBox(width: 8),
                            _buildTypeFilterTab('missing', 'Missing Pets ($missingCount)', color: const Color(0xFFC62828)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Row 2: Status Selection
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterTab('all', 'All Statuses'),
                            const SizedBox(width: 8),
                            _buildFilterTab('open', 'Needs Help ($openCount)', color: Colors.redAccent),
                            const SizedBox(width: 8),
                            _buildFilterTab('in progress', 'Responding ($inProgressCount)', color: Colors.blue),
                            const SizedBox(width: 8),
                            _buildFilterTab('rescued', 'Rescued ($rescuedCount)', color: Colors.green),
                            const SizedBox(width: 8),
                            _buildFilterTab('closed', 'Closed ($closedCount)', color: Colors.grey),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Reports Content
                if (_isMapView)
                  _buildLiveMap(filtered, isDesktop)
                else if (filtered.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(48),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.pets, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'No reports found',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (isDesktop)
                  _buildDesktopTable(filtered)
                else
                  _buildMobileCards(filtered),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String count, IconData icon, Color color, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilterTab(String key, String label, {Color? color}) {
    final isSelected = _selectedTypeFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: color ?? AppTheme.primaryOrange,
      backgroundColor: Colors.grey[100],
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
      onSelected: (val) {
        if (val) setState(() => _selectedTypeFilter = key);
      },
    );
  }

  Widget _buildFilterTab(String key, String label, {Color? color}) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: color ?? AppTheme.primaryOrange,
      backgroundColor: Colors.grey[100],
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
      onSelected: (val) {
        if (val) setState(() => _selectedFilter = key);
      },
    );
  }

  Widget _buildDesktopTable(List<Map<String, dynamic>> reports) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF9F9FB)),
          horizontalMargin: 24,
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('Photo', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Animal & ID', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Condition & Description', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Reported At', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: reports.map((report) {
            final key = report['reportKey'] ?? report['id'] ?? '';
            final petType = report['petType'] ?? 'Animal';
            final desc = report['description'] ?? 'No description';
            final address = report['address'] ?? 'No address';
            final status = (report['status'] ?? 'Open').toString();
            final imageUrl = report['imageUrl']?.toString();
            final timeStr = _formatDate(report['timestamp']);
            final statusColor = _getStatusColor(status);
            final isMissing = (report['reportType'] == 'missing') || (report['isMissingPet'] == true);
            final petName = report['petName']?.toString();
            final contactPhone = report['contactPhone']?.toString();

            return DataRow(
              cells: [
                DataCell(
                  InkWell(
                    onTap: () => _showImageDialog(context, imageUrl, petType),
                    child: _buildPetThumbnail(imageUrl, size: 48),
                  ),
                ),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(petType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          if (isMissing) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFEF9A9A)),
                              ),
                              child: const Text(
                                'MISSING',
                                style: TextStyle(
                                  color: Color(0xFFC62828),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (isMissing && petName != null && petName.isNotEmpty)
                        Text(
                          'Pet: $petName',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC62828)),
                        ),
                      if (isMissing && contactPhone != null && contactPhone.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.phone, size: 10, color: Colors.grey[700]),
                            const SizedBox(width: 2),
                            Text(
                              contactPhone,
                              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      Text(
                        '#${key.length > 8 ? key.substring(0, 8) : key}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                DataCell(
                  PopupMenuButton<String>(
                    tooltip: 'Change Status',
                    onSelected: (newVal) => _updateStatus(key, newVal),
                    itemBuilder: (c) => [
                      const PopupMenuItem(value: 'Open', child: Text('Open (Needs Help)')),
                      const PopupMenuItem(value: 'In Progress', child: Text('In Progress (Responding)')),
                      const PopupMenuItem(value: 'Rescued', child: Text('Rescued')),
                      const PopupMenuItem(value: 'Closed', child: Text('Closed')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, size: 14, color: statusColor),
                        ],
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Text(timeStr, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Open Maps',
                        icon: const Icon(Icons.map_outlined, size: 18, color: AppTheme.primaryTeal),
                        onPressed: () {
                          double? pLat;
                          double? pLng;
                          final rLat = report['lat'];
                          final rLng = report['lng'];
                          if (rLat is num) pLat = rLat.toDouble();
                          if (rLng is num) pLng = rLng.toDouble();
                          if (pLat == null && rLat is String) pLat = double.tryParse(rLat);
                          if (pLng == null && rLng is String) pLng = double.tryParse(rLng);
                          final coords = (pLat != null && pLng != null) ? LatLng(pLat, pLng) : const LatLng(14.5320, 121.0781);
                          AdminMapDialog.showLocation(
                            context,
                            location: coords,
                            title: isMissing ? 'Last Seen: ${petName ?? petType}' : 'Reported Stray: $petType',
                            landmark: address,
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'View Details',
                        icon: const Icon(Icons.visibility_outlined, size: 18, color: AppTheme.primaryOrange),
                        onPressed: () => _showReportDetailsDialog(context, report),
                      ),
                      IconButton(
                        tooltip: 'Delete Report',
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        onPressed: () => _confirmDeleteReport(context, key, petType),
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
  );
  }

  Widget _buildMobileCards(List<Map<String, dynamic>> reports) {
    return Column(
      children: reports.map((report) {
        final key = report['reportKey'] ?? report['id'] ?? '';
        final petType = report['petType'] ?? 'Animal';
        final desc = report['description'] ?? 'No description';
        final address = report['address'] ?? 'No address';
        final status = (report['status'] ?? 'Open').toString();
        final imageUrl = report['imageUrl']?.toString();
        final timeStr = _formatDate(report['timestamp']);
        final statusColor = _getStatusColor(status);
        final isMissing = (report['reportType'] == 'missing') || (report['isMissingPet'] == true);
        final petName = report['petName']?.toString();
        final contactPhone = report['contactPhone']?.toString();

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _showImageDialog(context, imageUrl, petType),
                      child: _buildPetThumbnail(imageUrl, size: 64),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  petType,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isMissing) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFEF9A9A)),
                                  ),
                                  child: const Text(
                                    'MISSING',
                                    style: TextStyle(
                                      color: Color(0xFFC62828),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ],
                          ),
                          if (isMissing && petName != null && petName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Name: $petName', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFC62828)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                          if (isMissing && contactPhone != null && contactPhone.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Owner Phone: $contactPhone', style: TextStyle(fontSize: 11, color: Colors.grey[700]), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 4),
                          Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(desc, style: const TextStyle(fontSize: 13, color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place, size: 14, color: AppTheme.primaryOrange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(address, style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const Divider(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryTeal,
                          side: const BorderSide(color: AppTheme.primaryTeal),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label: const Text('Open Map', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          double? pLat;
                          double? pLng;
                          final rLat = report['lat'];
                          final rLng = report['lng'];
                          if (rLat is num) pLat = rLat.toDouble();
                          if (rLng is num) pLng = rLng.toDouble();
                          if (pLat == null && rLat is String) pLat = double.tryParse(rLat);
                          if (pLng == null && rLng is String) pLng = double.tryParse(rLng);
                          final coords = (pLat != null && pLng != null) ? LatLng(pLat, pLng) : const LatLng(14.5320, 121.0781);
                          AdminMapDialog.showLocation(
                            context,
                            location: coords,
                            title: isMissing ? 'Last Seen: ${petName ?? petType}' : 'Reported Stray: $petType',
                            landmark: address,
                          );
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        label: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        onPressed: () => _confirmDeleteReport(context, key, petType),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('Details', style: TextStyle(fontSize: 12)),
                        onPressed: () => _showReportDetailsDialog(context, report),
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
  }

  Widget _buildLiveMap(List<Map<String, dynamic>> filteredReports, bool isDesktop) {
    final List<Marker> markers = [];
    LatLng centerPos = const LatLng(14.5320, 121.0781); // Metro East / Manila center

    for (final report in filteredReports) {
      final lat = (report['lat'] as num?)?.toDouble() ?? (report['latitude'] as num?)?.toDouble();
      final lng = (report['lng'] as num?)?.toDouble() ?? (report['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final point = LatLng(lat, lng);
      centerPos = point;
      final status = (report['status'] ?? 'Open').toString();
      final color = _getStatusColor(status);
      final isMissing = (report['isMissing'] == true || (report['reportType'] ?? '').toString().toLowerCase() == 'missing');

      markers.add(
        Marker(
          point: point,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedReportForMap = report;
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                decoration: BoxDecoration(
                  color: isMissing ? const Color(0xFFC62828) : color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Center(
                  child: Icon(
                    isMissing ? Icons.person_search_rounded : Icons.pets,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 600,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centerPos,
              initialZoom: 13,
              onTap: (_, __) {
                if (_selectedReportForMap != null) {
                  setState(() => _selectedReportForMap = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.saveapaw.adminweb',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          // Map header badge
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.emergency, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${markers.length} Live Incident Pin${markers.length == 1 ? '' : 's'} on Map',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          // Selected report card popup
          if (_selectedReportForMap != null)
            Positioned(
              left: 20,
              right: isDesktop ? null : 20,
              bottom: 20,
              width: isDesktop ? 380 : null,
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 10,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(_selectedReportForMap!['status'] ?? 'Open').withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (_selectedReportForMap!['status'] ?? 'Open').toString().toUpperCase(),
                              style: TextStyle(
                                color: _getStatusColor(_selectedReportForMap!['status'] ?? 'Open'),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (_selectedReportForMap!['petName'] ?? _selectedReportForMap!['petType'] ?? 'Emergency Report').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _selectedReportForMap = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (_selectedReportForMap!['landmark'] ?? _selectedReportForMap!['address'] ?? _selectedReportForMap!['location'] ?? 'Location coordinates provided').toString(),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final rep = _selectedReportForMap!;
                                setState(() => _selectedReportForMap = null);
                                _showReportDetailsDialog(context, rep);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryOrange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('View & Manage Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
