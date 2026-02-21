import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.api});

  final ApiClient api;

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final _locationService = LocationService();
  final MapController _mapController = MapController();

  LatLng _center = const LatLng(18.5204, 73.8567); // Pune default
  List<_ZoneCircle> _zones = [];
  final List<_ZoneCircle> _userMarkedZones = [];
  List<_ResourceMarker> _resources = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = '';
      });

      try {
        // We still fetch position for the "My Location" marker, but we don't move the map center automatically
        // to avoid jumping to San Francisco (emulator default) on app open.
        final pos = await _locationService.getCurrentPosition().timeout(
          const Duration(seconds: 3),
        );
        if (mounted)
          setState(() => _center = LatLng(pos.latitude, pos.longitude));
      } catch (_) {}

      // Fetch zones, resources, and sos
      List<dynamic> zonesList = <dynamic>[];
      dynamic sosRaw;
      try {
        final disastersRaw = await widget.api.get('/api/v1/disasters');
        final disasters = disastersRaw is List ? disastersRaw : <dynamic>[];
        for (final d in disasters) {
          final disaster = d as Map<String, dynamic>;
          final id = (disaster['id'] ?? '').toString();
          if (id.isEmpty) continue;
          try {
            final reliefRaw = await widget.api.get(
              '/api/v1/disasters/$id/relief-zones',
            );
            if (reliefRaw is List) zonesList.addAll(reliefRaw);
          } catch (_) {}
        }
        if (zonesList.isEmpty) {
          final coordinatorZones = await widget.api.get(
            '/api/v1/coordinator/zones',
          );
          zonesList = coordinatorZones is List ? coordinatorZones : <dynamic>[];
        }
        sosRaw = await widget.api.get('/api/v1/coordinator/sos');
      } catch (_) {}

      final zones = <_ZoneCircle>[];

      for (final z in zonesList) {
        final zone = z as Map<String, dynamic>;
        final lat = parseLat(zone['center_lat']);
        final lng = parseLng(zone['center_lng']);
        if (lat == null || lng == null) continue;

        zones.add(
          _ZoneCircle(
            id: (zone['id'] ?? '').toString(),
            name: (zone['name'] ?? 'Zone').toString(),
            severity: (zone['severity'] ?? 'red').toString(),
            radiusMeters: parseLat(zone['radius_meters']) ?? 500,
            center: LatLng(lat, lng),
          ),
        );
      }

      final markers = <_ResourceMarker>[];

      final resourcesRaw = await widget.api.get('/api/v1/resources');
      final resources = resourcesRaw is List ? resourcesRaw : <dynamic>[];

      for (final item in resources) {
        final r = item as Map<String, dynamic>;
        final parsed = _parsePoint(r['current_location']);
        if (parsed == null) continue;
        markers.add(
          _ResourceMarker(
            id: (r['id'] ?? '').toString(),
            type: (r['type'] ?? 'Resource').toString(),
            status: (r['status'] ?? '').toString(),
            point: parsed,
          ),
        );
      }

      final sosAlerts = sosRaw is List ? sosRaw : <dynamic>[];
      for (final item in sosAlerts) {
        final s = item as Map<String, dynamic>;
        final parsed = _parsePoint(s['location']);
        if (parsed == null) continue;
        markers.add(
          _ResourceMarker(
            id: (s['id'] ?? '').toString(),
            type: 'SOS',
            status: (s['status'] ?? '').toString(),
            point: parsed,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _zones = zones;
        _resources = markers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  LatLng? _parsePoint(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final lat = parseLat(raw['lat']);
      final lng = parseLng(raw['lng']);
      if (lat != null && lng != null) return LatLng(lat, lng);

      if (raw['coordinates'] is List &&
          (raw['coordinates'] as List).length >= 2) {
        final coords = raw['coordinates'] as List;
        final lngFromCoords = parseLng(coords[0]);
        final latFromCoords = parseLat(coords[1]);
        if (latFromCoords != null && lngFromCoords != null) {
          return LatLng(latFromCoords, lngFromCoords);
        }
      }
    }

    if (raw is String && raw.startsWith('POINT(') && raw.endsWith(')')) {
      final parts = raw
          .replaceFirst('POINT(', '')
          .replaceFirst(')', '')
          .split(' ');
      if (parts.length == 2) {
        final lng = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  _error,
                  style: const TextStyle(color: AppColors.criticalRed),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _zones.isNotEmpty
                          ? _zones.first.center
                          : _center,
                      initialZoom: 12,
                      onLongPress: (tapPosition, latLng) {
                        setState(() {
                          _userMarkedZones.add(
                            _ZoneCircle(
                              id: 'local-${DateTime.now().millisecondsSinceEpoch}',
                              name: 'User Marked Zone',
                              severity: 'blue',
                              radiusMeters: 250,
                              center: latLng,
                            ),
                          );
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Zone marker added (long-press).'),
                          ),
                        );
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sahyog_app',
                      ),
                      CircleLayer(
                        circles: _zones
                            .map(
                              (z) => CircleMarker(
                                point: z.center,
                                radius: max(40, z.radiusMeters / 5),
                                useRadiusInMeter: true,
                                color: _severityColor(
                                  z.severity,
                                ).withValues(alpha: 0.16),
                                borderColor: _severityColor(z.severity),
                                borderStrokeWidth: 2,
                              ),
                            )
                            .toList(),
                      ),
                      CircleLayer(
                        circles: _userMarkedZones
                            .map(
                              (z) => CircleMarker(
                                point: z.center,
                                radius: z.radiusMeters,
                                useRadiusInMeter: true,
                                color: AppColors.primaryGreen.withValues(
                                  alpha: 0.16,
                                ),
                                borderColor: AppColors.primaryGreen,
                                borderStrokeWidth: 2,
                              ),
                            )
                            .toList(),
                      ),
                      MarkerLayer(
                        markers: _resources.map((r) {
                          final isSos = r.type == 'SOS';
                          return Marker(
                            point: r.point,
                            width: 120,
                            height: 60,
                            child: isSos
                                ? _SosMarker()
                                : Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              blurRadius: 6,
                                              color: Color(0x22000000),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          r.type,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.location_on,
                                        color: AppColors.primaryGreen,
                                        size: 26,
                                      ),
                                    ],
                                  ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 16,
                    bottom: 60, // moved up to avoid overlapping with FAB
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: "map_my_location",
                          mini: true,
                          onPressed: () async {
                            try {
                              final pos = await _locationService
                                  .getCurrentPosition()
                                  .timeout(const Duration(seconds: 5));
                              final ll = LatLng(pos.latitude, pos.longitude);
                              _mapController.move(ll, 15);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Location unavailable: $e'),
                                  ),
                                );
                              }
                            }
                          },
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryGreen,
                          child: const Icon(Icons.my_location),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton(
                          heroTag: "map_zoom_in",
                          mini: true,
                          onPressed: () {
                            final zoom = _mapController.camera.zoom;
                            _mapController.move(
                              _mapController.camera.center,
                              zoom + 1,
                            );
                          },
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryGreen,
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton(
                          heroTag: "map_zoom_out",
                          mini: true,
                          onPressed: () {
                            final zoom = _mapController.camera.zoom;
                            _mapController.move(
                              _mapController.camera.center,
                              zoom - 1,
                            );
                          },
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryGreen,
                          child: const Icon(Icons.remove),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _LegendDot(color: AppColors.criticalRed, label: 'Red Zone'),
                  const SizedBox(width: 12),
                  _LegendDot(
                    color: AppColors.warningAmber,
                    label: 'Yellow Zone',
                  ),
                  const SizedBox(width: 12),
                  _LegendDot(color: AppColors.infoBlue, label: 'Blue Zone'),
                  _LegendDot(color: AppColors.criticalRed, label: 'SOS Alert'),
                  _LegendDot(
                    color: AppColors.primaryGreen,
                    label: 'User Marked',
                  ),
                  const Spacer(),
                  Text('Resources/SOS: ${_resources.length}'),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'yellow':
        return AppColors.warningAmber;
      case 'blue':
        return AppColors.infoBlue;
      default:
        return AppColors.criticalRed;
    }
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(radius: 6, backgroundColor: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _ZoneCircle {
  _ZoneCircle({
    required this.id,
    required this.name,
    required this.severity,
    required this.radiusMeters,
    required this.center,
  });

  final String id;
  final String name;
  final String severity;
  final double radiusMeters;
  final LatLng center;
}

class _ResourceMarker {
  _ResourceMarker({
    required this.id,
    required this.type,
    required this.status,
    required this.point,
  });

  final String id;
  final String type;
  final String status;
  final LatLng point;
}

class _SosMarker extends StatefulWidget {
  @override
  State<_SosMarker> createState() => _SosMarkerState();
}

class _SosMarkerState extends State<_SosMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer Ring
            Container(
              width: 50 * _controller.value,
              height: 50 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.criticalRed.withValues(
                  alpha: (1.0 - _controller.value) * 0.4,
                ),
                border: Border.all(
                  color: AppColors.criticalRed.withValues(
                    alpha: (1.0 - _controller.value) * 0.6,
                  ),
                  width: 1,
                ),
              ),
            ),
            // Middle Ring
            Container(
              width: 30 * _controller.value,
              height: 30 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.criticalRed.withValues(
                  alpha: (1.0 - _controller.value) * 0.3,
                ),
              ),
            ),
            // Solid Center Dot
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.criticalRed,
              ),
            ),
          ],
        );
      },
    );
  }
}
