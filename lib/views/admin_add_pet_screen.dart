import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/platform_picker.dart';
import '../theme/app_theme.dart';

class AdminAddPetScreen extends StatefulWidget {
  const AdminAddPetScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(24),
        child: AdminAddPetScreen(),
      ),
    );
  }

  @override
  State<AdminAddPetScreen> createState() => _AdminAddPetScreenState();
}

class _AdminAddPetScreenState extends State<AdminAddPetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _breedController = TextEditingController();
  final _ageController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'Dogs';
  String _selectedGender = 'Male';
  String? _base64Image;
  bool _isUploading = false;

  // Health checklist
  bool _isVaccinated = false;
  bool _isDewormed = false;
  bool _isMicrochipped = false;
  bool _isNeutered = false;
  bool _hasVitaminShots = false;

  final List<String> _categories = ['Dogs', 'Cats', 'Birds', 'Other'];
  final List<String> _genders = ['Male', 'Female'];

  int _selectedAgeNumber = 2;
  String _selectedAgeUnit = 'months';

  @override
  void initState() {
    super.initState();
    _updateAgeController();
  }

  void _updateAgeController() {
    final unitLabel = (_selectedAgeNumber == 1)
        ? (_selectedAgeUnit == 'months'
            ? 'month'
            : _selectedAgeUnit == 'years'
                ? 'year'
                : 'week')
        : _selectedAgeUnit;
    _ageController.text = '$_selectedAgeNumber $unitLabel';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _descriptionController.dispose();
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

  Future<void> _submitPet() async {
    if (!_formKey.currentState!.validate()) return;
    if (_base64Image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a photo of the pet'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final newRef = FirebaseDatabase.instance.ref().child('adoptionCenter').push();

      final enteredBreed = _breedController.text.trim();
      final effectiveBreed = enteredBreed.isNotEmpty ? enteredBreed : 'Mixed / Rescued';

      final petData = <String, dynamic>{
        'id': newRef.key,
        'name': _nameController.text.trim(),
        'category': _selectedCategory,
        'breed': effectiveBreed,
        'gender': _selectedGender,
        'age': _ageController.text.trim(),
        'description': _descriptionController.text.trim(),
        'imageUrl': _base64Image,
        'locationAddress': 'Save-A-Paws Rescue & Adoption Center',
        'isVaccinated': _isVaccinated,
        'isDewormed': _isDewormed,
        'isMicrochipped': _isMicrochipped,
        'isNeutered': _isNeutered,
        'hasVitaminShots': _hasVitaminShots,
        'isAdopted': false,
        'status': 'Available',
        'fosterId': user?.uid ?? 'admin_center',
        'fosterName': 'Save-A-Paws Admin Center',
        'createdAt': ServerValue.timestamp,
        'postedByAdmin': true,
      };

      await newRef.set(petData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_nameController.text.trim()} posted successfully to Adoption Catalog!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting pet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              title: const Row(
                children: [
                  Icon(Icons.pets, color: AppTheme.primaryOrange, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Post a Pet for Adoption (Admin)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                    // Photo Upload Card
                    GestureDetector(
                      onTap: _isUploading ? null : _pickImage,
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBFBFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _base64Image == null ? Colors.grey.shade300 : AppTheme.primaryOrange,
                            width: _base64Image == null ? 1.5 : 2,
                            style: BorderStyle.solid,
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
                                      color: AppTheme.primaryOrange.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.add_a_photo_rounded, size: 36, color: AppTheme.primaryOrange),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Upload Pet Photo',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'PNG, JPG, or WEBP supported',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Pet Name & Breed
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Pet Name *',
                              hintText: 'e.g. Milo, Luna',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextFormField(
                            controller: _breedController,
                            decoration: InputDecoration(
                              labelText: 'Breed',
                              hintText: 'e.g. Aspin, Shih Tzu, Persian',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Category & Gender
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCategory,
                            decoration: InputDecoration(
                              labelText: 'Animal Category',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (val) => setState(() => _selectedCategory = val ?? 'Dogs'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedGender,
                            decoration: InputDecoration(
                              labelText: 'Gender',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (val) => setState(() => _selectedGender = val ?? 'Male'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Age selector
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedAgeNumber,
                            decoration: InputDecoration(
                              labelText: 'Age Number',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            items: List.generate(20, (i) => i + 1)
                                .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedAgeNumber = val;
                                  _updateAgeController();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedAgeUnit,
                            decoration: InputDecoration(
                              labelText: 'Unit',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'months', child: Text('Months')),
                              DropdownMenuItem(value: 'years', child: Text('Years')),
                              DropdownMenuItem(value: 'weeks', child: Text('Weeks')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedAgeUnit = val;
                                  _updateAgeController();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Personality & Story *',
                        hintText: 'Describe temperament, backstory, good with kids/pets...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),

                    // Medical & Health Checklist
                    const Text(
                      'Medical & Health Record Checklist',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Vaccinated', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: const Text('Up to date with core 5-in-1 / anti-rabies shots', style: TextStyle(fontSize: 11)),
                            value: _isVaccinated,
                            activeColor: Colors.green,
                            onChanged: (v) => setState(() => _isVaccinated = v ?? false),
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Dewormed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: const Text('Internal parasite preventive treatments completed', style: TextStyle(fontSize: 11)),
                            value: _isDewormed,
                            activeColor: Colors.green,
                            onChanged: (v) => setState(() => _isDewormed = v ?? false),
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Neutered / Spayed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: const Text('Surgically sterilized to prevent overpopulation', style: TextStyle(fontSize: 11)),
                            value: _isNeutered,
                            activeColor: Colors.green,
                            onChanged: (v) => setState(() => _isNeutered = v ?? false),
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Microchipped', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: const Text('Permanent RFID identification chip implanted', style: TextStyle(fontSize: 11)),
                            value: _isMicrochipped,
                            activeColor: Colors.green,
                            onChanged: (v) => setState(() => _isMicrochipped = v ?? false),
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Vitamin & Health Supplements', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: const Text('Immune boosting supplements administered', style: TextStyle(fontSize: 11)),
                            value: _hasVitaminShots,
                            activeColor: Colors.green,
                            onChanged: (v) => setState(() => _hasVitaminShots = v ?? false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isUploading ? null : () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _submitPet,
                          icon: _isUploading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.publish_rounded, size: 18),
                          label: Text(
                            _isUploading ? 'Publishing Pet...' : 'Publish to Adoption Catalog',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryOrange,
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
