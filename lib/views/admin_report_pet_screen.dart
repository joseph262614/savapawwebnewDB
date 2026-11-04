import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/platform_picker.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_map_dialog.dart';

class AdminReportPetScreen extends StatefulWidget {
  final String initialType; // 'stray' or 'missing'

  const AdminReportPetScreen({super.key, this.initialType = 'stray'});

  static Future<void> show(BuildContext context, {String initialType = 'stray'}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: AdminReportPetScreen(initialType: initialType),
      ),
    );
  }

  @override
  State<AdminReportPetScreen> createState() => _AdminReportPetScreenState();
}

class _AdminReportPetScreenState extends State<AdminReportPetScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _reportType; // 'stray' or 'missing'

  final _petTypeController = TextEditingController(text: 'Dog');
  final _petNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _conditionController = TextEditingController(text: 'Injured / Needs Urgent Help');
  final _otherConditionController = TextEditingController();

  String? _base64Image;
  bool _isSubmitting = false;

  LatLng _selectedLocation = const LatLng(14.5320, 121.0781);
  late final MapController _miniMapController;

  final List<String> _animalTypes = ['Dog', 'Cat', 'Bird', 'Puppy / Kitten', 'Other Animal'];
  final List<String> _strayConditions = [
    'Injured / Needs Urgent Help',
    'Sick / Malnourished',
    'Abandoned in Box / Cage',
    'Safe but Stray / Wandering',
    'Trapped / In Danger',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _reportType = widget.initialType;
    _miniMapController = MapController();
  }

  Future<void> _openFullMapPicker() async {
    final result = await AdminMapDialog.pickLocation(
      context,
      initialLocation: _selectedLocation,
      landmark: _locationController.text.trim().isNotEmpty ? _locationController.text.trim() : null,
    );
    if (result != null && mounted) {
      setState(() {
        _selectedLocation = result;
      });
      _miniMapController.move(result, 15);
    }
  }

  Widget _buildEmbeddedMap(bool isMissing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isMissing ? 'Last Seen / Lost Location' : 'Location Found / Incident Location',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _miniMapController,
                options: MapOptions(
                  initialCenter: _selectedLocation,
                  initialZoom: 15,
                  onTap: (_, latLng) {
                    setState(() => _selectedLocation = latLng);
                    _miniMapController.move(latLng, 15);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'org.saveapaws.admin',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedLocation,
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
                  heroTag: 'admin_expand_map',
                  onPressed: _openFullMapPicker,
                  tooltip: 'Expand map / Open Full Map',
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.fullscreen, color: AppTheme.primaryOrange),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: FloatingActionButton.small(
                  heroTag: 'admin_recenter_map',
                  onPressed: () {
                    setState(() => _selectedLocation = const LatLng(14.5320, 121.0781));
                    _miniMapController.move(const LatLng(14.5320, 121.0781), 15);
                  },
                  tooltip: 'Reset Center',
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.blue, size: 18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.place, size: 18, color: AppTheme.primaryOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_selectedLocation.latitude.toStringAsFixed(4)}, ${_selectedLocation.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: _openFullMapPicker,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new, size: 14, color: AppTheme.primaryOrange),
                    SizedBox(width: 4),
                    Text(
                      'Open Maps',
                      style: TextStyle(
                        color: AppTheme.primaryOrange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _petTypeController.dispose();
    _petNameController.dispose();
    _contactPhoneController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _conditionController.dispose();
    _otherConditionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await pickImageWeb();
      if (picked != null) {
        setState(() {
          _base64Image = "data:image/jpeg;base64,${base64Encode(picked.bytes)}";
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_base64Image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a photo for the report'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final newRef = FirebaseDatabase.instance.ref().child('reports').push();

      final isMissing = _reportType == 'missing';

      final reportData = <String, dynamic>{
        'id': newRef.key,
        'reportKey': newRef.key,
        'reportType': _reportType,
        'isMissingPet': isMissing,
        'petType': _petTypeController.text.trim(),
        'address': _locationController.text.trim(),
        'lat': _selectedLocation.latitude,
        'lng': _selectedLocation.longitude,
        'description': _descriptionController.text.trim(),
        'imageUrl': _base64Image,
        'status': 'Open',
        'timestamp': ServerValue.timestamp,
        'userId': user?.uid ?? 'admin_coordinator',
        'userEmail': user?.email ?? 'admin@saveapaw.org',
        'reportedBy': 'Admin / Rescue Coordinator',
        'reportedByRole': 'admin',
      };

      if (isMissing) {
        reportData['petName'] = _petNameController.text.trim();
        reportData['contactPhone'] = _contactPhoneController.text.trim();
        reportData['condition'] = 'Missing Pet';
      } else {
        reportData['condition'] = _conditionController.text == 'Other'
            ? (_otherConditionController.text.trim().isNotEmpty
                ? 'Other: ${_otherConditionController.text.trim()}'
                : 'Other')
            : _conditionController.text.trim();
      }

      await newRef.set(reportData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMissing
                  ? '🚨 Missing Pet "${_petNameController.text.trim()}" alert broadcasted successfully!'
                  : '🚨 Stray animal report submitted to rescue dispatch hub!',
            ),
            backgroundColor: isMissing ? const Color(0xFFC62828) : AppTheme.primaryOrange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting report: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMissing = _reportType == 'missing';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: Row(
                children: [
                  Icon(
                    isMissing ? Icons.person_search_rounded : Icons.emergency_rounded,
                    color: isMissing ? const Color(0xFFC62828) : Colors.redAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isMissing ? 'Report a Missing Pet' : 'Report a Stray Pet in Need',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0.5,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Segmented Switcher: Stray Pet vs Missing Pet
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _reportType = 'stray'),
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: !isMissing ? AppTheme.primaryOrange : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: !isMissing
                                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)]
                                      : [],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.pets,
                                      size: 18,
                                      color: !isMissing ? Colors.white : Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Report Stray Pet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: !isMissing ? Colors.white : Colors.grey.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _reportType = 'missing'),
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isMissing ? const Color(0xFFC62828) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: isMissing
                                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)]
                                      : [],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_search_rounded,
                                      size: 18,
                                      color: isMissing ? Colors.white : Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Report Missing Pet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: isMissing ? Colors.white : Colors.grey.shade800,
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
                    const SizedBox(height: 14),

                    // Context info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMissing ? const Color(0xFFFFF3F3) : const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isMissing ? const Color(0xFFFFCDD2) : const Color(0xFFFFE082),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isMissing ? Icons.info_outline : Icons.warning_amber_rounded,
                            size: 18,
                            color: isMissing ? const Color(0xFFC62828) : const Color(0xFFF57F17),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isMissing
                                  ? 'Broadcasting a missing pet will alert rescuers, volunteers, and the community to help locate and reunite them with their family.'
                                  : 'Reporting a stray animal creates a rescue ticket visible on the rescue dispatch map for urgent volunteer intervention.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMissing ? const Color(0xFFB71C1C) : const Color(0xFFE65100),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Photo Upload Card
                    GestureDetector(
                      onTap: _isSubmitting ? null : _pickImage,
                      child: Container(
                        height: 190,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBFBFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _base64Image == null
                                ? Colors.grey.shade300
                                : (isMissing ? const Color(0xFFC62828) : AppTheme.primaryOrange),
                            width: _base64Image == null ? 1.5 : 2,
                          ),
                        ),
                        child: _base64Image != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.memory(
                                      base64Decode(_base64Image!.split(',').last),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 12,
                                    right: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black87.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.photo_camera, color: Colors.white, size: 14),
                                          SizedBox(width: 6),
                                          Text('Change Photo', style: TextStyle(color: Colors.white, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: (isMissing ? const Color(0xFFC62828) : AppTheme.primaryOrange)
                                          .withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.add_a_photo_rounded,
                                      size: 36,
                                      color: isMissing ? const Color(0xFFC62828) : AppTheme.primaryOrange,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    isMissing ? 'Upload Photo of Missing Pet' : 'Upload Photo of Stray Animal',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Clear photo helps rescuers identify the animal quickly',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Missing Pet Specific Fields
                    if (isMissing) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _petNameController,
                              decoration: InputDecoration(
                                labelText: 'Pet Name *',
                                hintText: 'e.g. Bella, Max',
                                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Required for missing pet' : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _contactPhoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Owner / Contact Phone *',
                                hintText: 'e.g. 0917-123-4567',
                                prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Animal Type & Condition
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _petTypeController.text,
                            decoration: InputDecoration(
                              labelText: 'Animal Type',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            items: _animalTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _petTypeController.text = val);
                            },
                          ),
                        ),
                        if (!isMissing) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _conditionController.text,
                              decoration: InputDecoration(
                                labelText: 'Observed Condition',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              items: _strayConditions.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _conditionController.text = val);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!isMissing && _conditionController.text == 'Other') ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _otherConditionController,
                        decoration: InputDecoration(
                          labelText: 'Specify Observed Condition Details *',
                          hintText: 'e.g. Broken wing, trapped in storm drain, extreme dehydration...',
                          prefixIcon: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryOrange, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (val) {
                          if (!isMissing && _conditionController.text == 'Other' && (val == null || val.trim().isEmpty)) {
                            return 'Please specify the observed condition details';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Location Map (Photo 1)
                    _buildEmbeddedMap(isMissing),
                    const SizedBox(height: 16),

                    // Location Found / Landmark (Photo 2)
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: isMissing ? 'Last Seen Location / Landmark *' : 'Location Found / Landmark *',
                        hintText: 'e.g. Corner Rizal St. near Central Park, Barangay San Jose',
                        prefixIcon: const Icon(Icons.place_outlined, color: AppTheme.primaryOrange, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Please specify location' : null,
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: isMissing ? 'Description & Distinctive Marks *' : 'Condition Details & Urgency *',
                        hintText: isMissing
                            ? 'e.g. Wearing a blue collar, white patch on chest, responds to "Milo", very friendly...'
                            : 'e.g. Limping left rear leg, seems weak and seeking shade near pharmacy...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submitReport,
                          icon: _isSubmitting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Icon(isMissing ? Icons.campaign_rounded : Icons.send_rounded, size: 18),
                          label: Text(
                            _isSubmitting
                                ? 'Submitting...'
                                : (isMissing ? 'Broadcast Missing Pet Alert' : 'Submit Stray Animal Report'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isMissing ? const Color(0xFFC62828) : AppTheme.primaryOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
