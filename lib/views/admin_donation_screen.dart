import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../utils/platform_picker.dart';
import '../theme/app_theme.dart';

class AdminDonationScreen extends StatefulWidget {
  final bool embeddedMode;

  const AdminDonationScreen({super.key, this.embeddedMode = false});

  @override
  State<AdminDonationScreen> createState() => _AdminDonationScreenState();
}

class _AdminDonationScreenState extends State<AdminDonationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _notesController = TextEditingController();

  static const List<String> _presetBanks = [
    'BDO',
    'BPI',
    'GoTyme',
    'GCash',
    'MariBank',
    'Maya',
    'Other',
  ];
  String? _selectedBank;

  Uint8List? _qrImageBytes;
  String? _qrImageFileName;
  String? _selectedQrBase64;
  String? _existingQrImageUrl;
  bool _isLoading = false;
  bool _isFetching = true;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    try {
      final snap = await FirebaseDatabase.instance.ref().child('donation_info').get();
      if (snap.exists && snap.value is Map) {
        final data = snap.value as Map;
        final rawBank = data['bankName']?.toString().trim() ?? '';
        String? matchedBank;
        if (rawBank.isNotEmpty) {
          matchedBank = _presetBanks.firstWhere(
            (b) => b.toLowerCase() == rawBank.toLowerCase(),
            orElse: () => 'Other',
          );
        }
        if (mounted) {
          setState(() {
            _accountNameController.text = data['accountName']?.toString() ?? '';
            _bankNameController.text = (matchedBank != null && matchedBank != 'Other') ? matchedBank : rawBank;
            _selectedBank = matchedBank;
            _accountNumberController.text = data['accountNumber']?.toString() ?? '';
            _notesController.text = data['notes']?.toString() ?? '';
            _existingQrImageUrl = data['qrImageUrl']?.toString();
            _isFetching = false;
          });
        }
      } else {
        if (mounted) setState(() => _isFetching = false);
      }
    } catch (e) {
      debugPrint('AdminDonationScreen: Error loading donation info: $e');
      if (mounted) setState(() => _isFetching = false);
    }
  }

  @override
  void dispose() {
    _accountNameController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _pickQrImage() async {
    try {
      final picked = await pickImageWeb();
      if (picked != null) {
        final base64String = "data:image/jpeg;base64,${base64Encode(picked.bytes)}";
        setState(() {
          _qrImageBytes = picked.bytes;
          _qrImageFileName = picked.name;
          _selectedQrBase64 = base64String;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Selected image: ${picked.name} (${(picked.bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)'),
              backgroundColor: Colors.teal,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking QR image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveDonationInfo() async {
    if (!_formKey.currentState!.validate()) return;

    final hasNewImage = _selectedQrBase64 != null && _selectedQrBase64!.isNotEmpty;
    final hasExistingImage = _existingQrImageUrl != null && _existingQrImageUrl!.isNotEmpty;

    if (!hasNewImage && !hasExistingImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a QR Code image (e.g. GCash, Maya, or Bank QR)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final String qrImageToSave = hasNewImage ? _selectedQrBase64! : _existingQrImageUrl!;

      final data = {
        'accountName': _accountNameController.text.trim(),
        'bankName': _bankNameController.text.trim(),
        'accountNumber': _accountNumberController.text.trim(),
        'notes': _notesController.text.trim(),
        'qrImageUrl': qrImageToSave,
        'updatedAt': ServerValue.timestamp,
        'updatedBy': user?.uid ?? 'admin',
      };

      await FirebaseDatabase.instance.ref().child('donation_info').set(data);

      if (mounted) {
        setState(() {
          _existingQrImageUrl = qrImageToSave;
          _qrImageBytes = null;
          _qrImageFileName = null;
          _selectedQrBase64 = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Donation info & QR Code updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save donation info: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildQrPreview() {
    if (_qrImageBytes != null) {
      return Image.memory(
        _qrImageBytes!,
        fit: BoxFit.contain,
      );
    }

    if (_existingQrImageUrl != null && _existingQrImageUrl!.isNotEmpty) {
      if (_existingQrImageUrl!.startsWith('data:image')) {
        try {
          return Image.memory(
            base64Decode(_existingQrImageUrl!.split(',').last),
            fit: BoxFit.contain,
          );
        } catch (_) {}
      }
      return Image.network(
        _existingQrImageUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.qr_code_2, size: 80, color: Colors.grey),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(
          'Upload Donation QR Code',
          style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Click to choose GCash, Maya, or Bank QR photo',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _isFetching
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryOrange))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  return isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _buildFormCard()),
                            const SizedBox(width: 24),
                            Expanded(flex: 4, child: _buildLivePreviewCard()),
                          ],
                        )
                      : Column(
                          children: [
                            _buildFormCard(),
                            const SizedBox(height: 24),
                            _buildLivePreviewCard(),
                          ],
                        );
                },
              ),
            ),
          );

    if (widget.embeddedMode) {
      return Container(
        color: const Color(0xFFF5F5F8),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        title: const Text('Donation & QR Setup'),
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: content,
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.volunteer_activism, color: AppTheme.primaryOrange, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Donation Account Details',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Configure bank details and QR code shown to donors',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            // QR Code Upload Area
            const Text(
              'Official QR Code Image *',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _pickQrImage,
                child: Container(
                  height: 230,
                  decoration: BoxDecoration(
                    color: _qrImageBytes != null ? const Color(0xFFE8F5E9) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _qrImageBytes != null ? Colors.green.shade400 : Colors.grey[300]!,
                      width: _qrImageBytes != null ? 2 : 1.5,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildQrPreview(),
                      ),
                      if (_qrImageFileName != null)
                        Positioned(
                          top: 10,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _qrImageFileName!,
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_qrImageBytes != null) ...[
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _qrImageBytes = null;
                                    _qrImageFileName = null;
                                    _selectedQrBase64 = null;
                                  });
                                },
                                tooltip: 'Remove selected image',
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            ElevatedButton.icon(
                              onPressed: _pickQrImage,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryOrange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.upload, size: 16),
                              label: Text(
                                _qrImageBytes != null || (_existingQrImageUrl != null && _existingQrImageUrl!.isNotEmpty)
                                    ? 'Change QR Image'
                                    : 'Select QR Image',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Account Name
            TextFormField(
              controller: _accountNameController,
              decoration: const InputDecoration(
                labelText: 'Account / Organization Name *',
                hintText: 'e.g. Save A Paw Animal Rescue Foundation',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter the account or organization name' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Bank / E-Wallet Provider Selection
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance, size: 16, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    const Text(
                      'Bank / E-Wallet Provider *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presetBanks.map((bank) {
                    final isSelected = _selectedBank == bank;
                    return ChoiceChip(
                      label: Text(bank == 'Other' ? 'Others...' : bank),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedBank = bank;
                          if (bank != 'Other') {
                            _bankNameController.text = bank;
                          } else if (_presetBanks.contains(_bankNameController.text)) {
                            _bankNameController.clear();
                          }
                        });
                      },
                      selectedColor: const Color(0xFFFF926B).withValues(alpha: 0.25),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFFE65100) : Colors.grey.shade300,
                        width: isSelected ? 1.5 : 1,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected ? const Color(0xFFE65100) : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12.5,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                FormField<String>(
                  initialValue: _selectedBank,
                  validator: (_) {
                    if (_selectedBank == null || _selectedBank!.isEmpty) {
                      return 'Please select a bank or e-wallet provider';
                    }
                    return null;
                  },
                  builder: (FormFieldState<String> state) {
                    return InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Choose Provider *',
                        prefixIcon: const Icon(Icons.account_balance),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        errorText: state.hasError ? state.errorText : null,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBank,
                          isExpanded: true,
                          hint: const Text('Select BDO, BPI, GoTyme, GCash, MariBank, Maya, or Others'),
                          items: _presetBanks.map((bank) {
                            return DropdownMenuItem<String>(
                              value: bank,
                              child: Text(
                                bank == 'Other' ? 'Others (Type bank / e-wallet name)' : bank,
                                style: TextStyle(
                                  fontWeight: bank == 'Other' ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedBank = val;
                              state.didChange(val);
                              if (val != 'Other' && val != null) {
                                _bankNameController.text = val;
                              } else if (val == 'Other') {
                                if (_presetBanks.contains(_bankNameController.text)) {
                                  _bankNameController.clear();
                                }
                              }
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
                if (_selectedBank == 'Other') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bankNameController,
                    decoration: const InputDecoration(
                      labelText: 'Type Bank / E-Wallet Name *',
                      hintText: 'e.g. UnionBank, SeaBank, LandBank, GrabPay, Coins.ph',
                      prefixIcon: Icon(Icons.edit_outlined),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Please enter the bank or e-wallet name' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Account Number
            TextFormField(
              controller: _accountNumberController,
              decoration: const InputDecoration(
                labelText: 'Account / Mobile Number *',
                hintText: 'e.g. 0912 345 6789 or 1234-5678-90',
                prefixIcon: Icon(Icons.credit_card),
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter the account number' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Instructions / Notes (Optional)',
                hintText: 'e.g. Please put your name in the remarks so we can acknowledge your gift!',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 28),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveDonationInfo,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Publish Donation Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreviewCard() {
    final accountName = _accountNameController.text.trim();
    final bankName = _bankNameController.text.trim();
    final accountNumber = _accountNumberController.text.trim();
    final notes = _notesController.text.trim();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.remove_red_eye_outlined, color: AppTheme.primaryTeal, size: 20),
                SizedBox(width: 8),
                Text(
                  'Donor Live Preview',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'This is how donors will view your donation setup in the app',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 24),

            // Preview Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Center(
                      child: _buildQrPreview(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    bankName.isNotEmpty ? bankName.toUpperCase() : 'BANK / E-WALLET',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryOrange),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    accountName.isNotEmpty ? accountName : 'Organization / Account Name',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      accountNumber.isNotEmpty ? accountNumber : '0000 0000 0000',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Color(0xFF00695C),
                      ),
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      notes,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
