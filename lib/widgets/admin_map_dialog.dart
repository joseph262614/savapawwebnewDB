import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../utils/platform_picker.dart';

class AdminMapDialog extends StatefulWidget {
  final LatLng initialLocation;
  final bool isPicker;
  final String title;
  final String? landmark;

  const AdminMapDialog({
    super.key,
    required this.initialLocation,
    this.isPicker = true,
    this.title = 'Mark Location on Map',
    this.landmark,
  });

  static Future<LatLng?> pickLocation(
    BuildContext context, {
    LatLng? initialLocation,
    String? landmark,
  }) {
    return showDialog<LatLng>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: AdminMapDialog(
          initialLocation: initialLocation ?? const LatLng(14.5320, 121.0781),
          isPicker: true,
          title: 'Mark Location on Map',
          landmark: landmark,
        ),
      ),
    );
  }

  static Future<void> showLocation(
    BuildContext context, {
    required LatLng location,
    String title = 'Reported Location',
    String? landmark,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: AdminMapDialog(
          initialLocation: location,
          isPicker: false,
          title: title,
          landmark: landmark,
        ),
      ),
    );
  }

  @override
  State<AdminMapDialog> createState() => _AdminMapDialogState();
}

class _AdminMapDialogState extends State<AdminMapDialog> {
  late LatLng _currentLocation;
  late final MapController _mapController;
  double _currentZoom = 15.5;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    _mapController = MapController();
  }

  void _zoomIn() {
    setState(() {
      _currentZoom = (_currentZoom + 1).clamp(3.0, 18.0);
      _mapController.move(_currentLocation, _currentZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom = (_currentZoom - 1).clamp(3.0, 18.0);
      _mapController.move(_currentLocation, _currentZoom);
    });
  }

  void _recenter() {
    _mapController.move(_currentLocation, _currentZoom);
  }

  void _openInGoogleMaps() {
    final url = 'https://www.google.com/maps/search/?api=1&query=${_currentLocation.latitude},${_currentLocation.longitude}';
    openUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.map_rounded, color: AppTheme.primaryOrange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                        ),
                        if (widget.landmark != null && widget.landmark!.isNotEmpty)
                          Text(
                            widget.landmark!,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Map Area
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _currentLocation,
                      initialZoom: _currentZoom,
                      onTap: widget.isPicker
                          ? (_, latLng) => setState(() => _currentLocation = latLng)
                          : null,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'org.saveapaws.admin',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentLocation,
                            width: 50,
                            height: 50,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_on,
                              size: 44,
                              color: AppTheme.primaryOrange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Top instruction banner (if picker)
                  if (widget.isPicker)
                    Positioned(
                      top: 14,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_rounded, size: 16, color: AppTheme.primaryOrange),
                              SizedBox(width: 8),
                              Text(
                                'Click anywhere on the map to pin the location',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Zoom Controls & Recenter
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_recenter',
                          onPressed: _recenter,
                          tooltip: 'Recenter Pin',
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.my_location, color: Colors.blue, size: 18),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_in',
                          onPressed: _zoomIn,
                          tooltip: 'Zoom In',
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.add, color: Colors.black87, size: 18),
                        ),
                        const SizedBox(height: 6),
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_out',
                          onPressed: _zoomOut,
                          tooltip: 'Zoom Out',
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.remove, color: Colors.black87, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom action & coordinates bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place, size: 16, color: AppTheme.primaryOrange),
                        const SizedBox(width: 6),
                        Text(
                          '${_currentLocation.latitude.toStringAsFixed(4)}, ${_currentLocation.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: _openInGoogleMaps,
                    icon: const Icon(Icons.open_in_new, size: 14, color: AppTheme.primaryOrange),
                    label: const Text('Open in Google Maps', style: TextStyle(color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(widget.isPicker ? 'Cancel' : 'Close'),
                  ),
                  if (widget.isPicker) ...[
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, _currentLocation),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Confirm Location', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
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
