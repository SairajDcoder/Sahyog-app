import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';

class CoordinatorDashboardTab extends StatefulWidget {
  const CoordinatorDashboardTab({
    super.key,
    required this.api,
    required this.user,
    required this.onNavigate,
  });

  final ApiClient api;
  final AppUser user;
  final void Function(int) onNavigate;

  @override
  State<CoordinatorDashboardTab> createState() =>
      _CoordinatorDashboardTabState();
}

class _CoordinatorDashboardTabState extends State<CoordinatorDashboardTab> {
  final MapController _miniMapController = MapController();

  bool _loading = true;
  String _error = '';
  Timer? _pollTimer;

  Map<String, dynamic> _ctx = {};
  List<Map<String, dynamic>> _recentSos = [];
  List<Map<String, dynamic>> _recentTasks = [];
  List<Map<String, dynamic>> _zones = [];

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      if (!silent) {
        setState(() {
          _loading = true;
          _error = '';
        });
      }

      final results = await Future.wait([
        widget.api.get('/api/v1/coordinator/context'),
        widget.api.get('/api/v1/coordinator/sos'),
        widget.api.get('/api/v1/coordinator/tasks'),
        widget.api.get('/api/v1/coordinator/zones'),
      ]);

      if (!mounted) return;
      setState(() {
        _ctx = (results[0] is Map<String, dynamic>)
            ? results[0] as Map<String, dynamic>
            : {};

        final sosList = (results[1] is List) ? results[1] as List : [];
        _recentSos = sosList
            .take(5)
            .map((e) => e as Map<String, dynamic>)
            .toList();

        final tasksList = (results[2] is List) ? results[2] as List : [];
        _recentTasks = tasksList
            .take(5)
            .map((e) => e as Map<String, dynamic>)
            .toList();

        final zonesList = (results[3] is List) ? results[3] as List : [];
        _zones = zonesList.map((e) => e as Map<String, dynamic>).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: AppColors.criticalRed)),
          _buildStatsRow(),
          const SizedBox(height: 12),
          _buildMiniMap(),
          const SizedBox(height: 12),
          _buildRecentTasks(),
          const SizedBox(height: 12),
          _buildRecentSos(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final stats = (_ctx['stats'] is Map<String, dynamic>)
        ? _ctx['stats'] as Map<String, dynamic>
        : {};
    final activeSos = (stats['active_sos'] ?? 0).toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              child: Text(
                widget.user.name.isNotEmpty
                    ? widget.user.name[0].toUpperCase()
                    : '?',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coordinator Dashboard',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('Active SOS: $activeSos • Zone Ops Live'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = (_ctx['stats'] is Map<String, dynamic>)
        ? _ctx['stats'] as Map<String, dynamic>
        : {};
    final tasks = (stats['tasks'] is Map<String, dynamic>)
        ? stats['tasks'] as Map<String, dynamic>
        : {};
    final needs = (stats['needs'] is Map<String, dynamic>)
        ? stats['needs'] as Map<String, dynamic>
        : {};

    final items = [
      (
        'Volunteers',
        stats['volunteers'] ?? 0,
        Icons.people_alt,
        AppColors.primaryGreen,
        1,
      ),
      ('Tasks', tasks['total'] ?? 0, Icons.assignment, Colors.blueAccent, 2),
      ('Needs', needs['total'] ?? 0, Icons.report_problem, Colors.orange, 3),
      ('SOS', stats['active_sos'] ?? 0, Icons.sos, AppColors.criticalRed, 4),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final (label, value, icon, color, tabIndex) = item;
          return SizedBox(
            width: 110,
            child: InkWell(
              onTap: () => widget.onNavigate(tabIndex),
              borderRadius: BorderRadius.circular(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  child: Column(
                    children: [
                      Icon(icon, size: 22, color: color),
                      const SizedBox(height: 4),
                      Text(
                        '$value',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMiniMap() {
    LatLng center = const LatLng(28.6139, 77.2090);
    if (_zones.isNotEmpty) {
      final first = _zones.first;
      final lat = parseLat(first['center_lat']);
      final lng = parseLng(first['center_lng']);
      if (lat != null && lng != null) {
        center = LatLng(lat, lng);
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 180,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _miniMapController,
              options: MapOptions(initialCenter: center, initialZoom: 11),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.sahyog_app',
                ),
                CircleLayer(
                  circles: _zones.map((zone) {
                    final lat = parseLat(zone['center_lat']);
                    final lng = parseLng(zone['center_lng']);
                    if (lat == null || lng == null) {
                      return const CircleMarker(point: LatLng(0, 0), radius: 0);
                    }
                    final severity = (zone['severity'] ?? 'red').toString();
                    final radius = parseLat(zone['radius_meters']) ?? 400;
                    final color = _severityColor(severity);
                    return CircleMarker(
                      point: LatLng(lat, lng),
                      radius: radius,
                      useRadiusInMeter: true,
                      color: color.withValues(alpha: 0.16),
                      borderColor: color,
                      borderStrokeWidth: 2,
                    );
                  }).toList(),
                ),
              ],
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'mini_map_zoom_in',
                    onPressed: () {
                      _miniMapController.move(
                        _miniMapController.camera.center,
                        _miniMapController.camera.zoom + 1,
                      );
                    },
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryGreen,
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'mini_map_zoom_out',
                    onPressed: () {
                      _miniMapController.move(
                        _miniMapController.camera.center,
                        _miniMapController.camera.zoom - 1,
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
    );
  }

  Widget _buildRecentTasks() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Tasks',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (_recentTasks.isEmpty)
              const Text('No active tasks.')
            else
              ..._recentTasks.map((task) {
                final title = (task['title'] ?? task['type'] ?? 'Task')
                    .toString();
                final status = (task['status'] ?? 'pending').toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.task, size: 14),
                  ),
                  title: Text(title, style: const TextStyle(fontSize: 13)),
                  trailing: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSos() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent SOS Alerts',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (_recentSos.isEmpty)
              const Text(
                'No active SOS alerts.',
                style: TextStyle(fontSize: 13),
              )
            else
              ..._recentSos.map((sos) {
                final status = (sos['status'] ?? 'triggered').toString();
                final vol = (sos['volunteer_name'] ?? 'Unknown').toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.criticalRed,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.sos, size: 14),
                  ),
                  title: Text(vol, style: const TextStyle(fontSize: 13)),
                  trailing: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'yellow':
        return Colors.amber;
      case 'blue':
        return Colors.blue;
      default:
        return AppColors.criticalRed;
    }
  }
}
