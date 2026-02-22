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
  String _searchQuery = '';
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
    return Scaffold(
      body: _loading && _ctx.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 10),
                  if (_error.isNotEmpty)
                    Text(
                      _error,
                      style: const TextStyle(color: AppColors.criticalRed),
                    ),
                  _buildMiniMap(),
                  const SizedBox(height: 12),
                  _buildStatsRow(),
                  const SizedBox(height: 12),
                  _buildRecentTasks(),
                  const SizedBox(height: 12),
                  _buildRecentSos(),
                  const SizedBox(height: 80), // Padding for FAB
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryGreen.withOpacity(0.15),
              foregroundColor: AppColors.primaryGreen,
              radius: 18,
              child: Text(
                widget.user.name.isNotEmpty
                    ? widget.user.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search alerts, tasks...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            Icon(Icons.search, color: Colors.grey.shade400, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = (_ctx['stats'] is Map<String, dynamic>)
        ? _ctx['stats'] as Map<String, dynamic>
        : {};
    final items = [
      (
        'Volunteers',
        stats['volunteers'] ?? 0,
        Icons.people_alt,
        AppColors.primaryGreen,
        10,
      ),
      (
        'Tasks',
        _recentTasks.length, // Or use a total count from stats if available
        Icons.assignment,
        Colors.blueAccent,
        11,
      ),
      (
        'Needs',
        stats['active_needs'] ?? 0,
        Icons.report_problem,
        Colors.orange,
        12,
      ),
      ('SOS', _recentSos.length, Icons.sos, AppColors.criticalRed, 3),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: items.map((item) {
          final (label, value, icon, color, tabIndex) = item;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 130,
              child: InkWell(
                onTap: () => widget.onNavigate(tabIndex),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$value',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
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
    LatLng center = const LatLng(18.5204, 73.8567);
    if (_zones.isNotEmpty) {
      final first = _zones.first;
      final lat = parseLat(first['center_lat']);
      final lng = parseLng(first['center_lng']);
      if (lat != null && lng != null) {
        center = LatLng(lat, lng);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onLongPress: () => widget.onNavigate(1),
        child: SizedBox(
          height: 200,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _miniMapController,
                options: MapOptions(initialCenter: center, initialZoom: 11),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.sahyog_app',
                  ),
                  CircleLayer(
                    circles: _zones.map((zone) {
                      final lat = parseLat(zone['center_lat']);
                      final lng = parseLng(zone['center_lng']);
                      if (lat == null || lng == null) {
                        return const CircleMarker(
                          point: LatLng(0, 0),
                          radius: 0,
                        );
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
      ),
    );
  }

  Widget _buildRecentTasks() {
    final filtered = _searchQuery.isEmpty
        ? _recentTasks
        : _recentTasks.where((task) {
            final title = (task['title'] ?? task['type'] ?? '')
                .toString()
                .toLowerCase();
            final status = (task['status'] ?? '').toString().toLowerCase();
            return title.contains(_searchQuery.toLowerCase()) ||
                status.contains(_searchQuery.toLowerCase());
          }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Tasks',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No active tasks right now',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filtered.map((task) {
                final title = (task['title'] ?? task['type'] ?? 'Task')
                    .toString();
                final status = (task['status'] ?? 'pending').toString();
                final isCompleted = status.toLowerCase() == 'completed';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? AppColors.primaryGreen
                              : Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.black87,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isCompleted
                                      ? AppColors.primaryGreen
                                      : Colors.blueAccent)
                                  .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: isCompleted
                                ? AppColors.primaryGreen
                                : Colors.blueAccent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSos() {
    final filtered = _searchQuery.isEmpty
        ? _recentSos
        : _recentSos.where((sos) {
            final vol = (sos['volunteer_name'] ?? '').toString().toLowerCase();
            final status = (sos['status'] ?? '').toString().toLowerCase();
            return vol.contains(_searchQuery.toLowerCase()) ||
                status.contains(_searchQuery.toLowerCase());
          }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent SOS Alerts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No SOS alerts — all clear',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filtered.map((sos) {
                final status = (sos['status'] ?? 'triggered').toString();
                final reporterName =
                    (sos['reporter_name'] ??
                            sos['reporter_phone'] ??
                            'Sahayanet User')
                        .toString();
                final isResolved = status.toLowerCase() == 'resolved';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isResolved
                              ? AppColors.primaryGreen
                              : AppColors.criticalRed,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          reporterName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.black87,
                            decoration: isResolved
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isResolved
                                      ? AppColors.primaryGreen
                                      : AppColors.criticalRed)
                                  .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: isResolved
                                ? AppColors.primaryGreen
                                : AppColors.criticalRed,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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

  double? parseLat(dynamic val) {
    if (val == null) return null;
    return double.tryParse(val.toString());
  }

  double? parseLng(dynamic val) {
    if (val == null) return null;
    return double.tryParse(val.toString());
  }
}
