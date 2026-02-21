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

  LatLng _center = const LatLng(28.6139, 77.2090);
  List<_ZoneCircle> _zones = [];
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
        final pos = await _locationService.getCurrentPosition();
        _center = LatLng(pos.latitude, pos.longitude);
      } catch (_) {}

      // Fetch global zones, resources, and sos
      dynamic zonesRaw;
      dynamic sosRaw;
      try {
        zonesRaw = await widget.api.get('/api/v1/coordinator/zones');
        sosRaw = await widget.api.get('/api/v1/coordinator/sos');
      } catch (_) {}

      final zonesList = zonesRaw is List ? zonesRaw : <dynamic>[];
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
              child: FlutterMap(
                options: MapOptions(initialCenter: _center, initialZoom: 12),
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
                  MarkerLayer(
                    markers: _resources.map((r) {
                      final isSos = r.type == 'SOS';
                      return Marker(
                        point: r.point,
                        width: 120,
                        height: 60,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSos
                                    ? AppColors.criticalRed
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isSos ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            Icon(
                              isSos ? Icons.sos : Icons.location_on,
                              color: isSos
                                  ? AppColors.criticalRed
                                  : AppColors.primaryGreen,
                              size: 26,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
