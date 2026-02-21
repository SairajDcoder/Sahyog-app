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
  });

  final ApiClient api;
  final AppUser user;

  @override
  State<CoordinatorDashboardTab> createState() =>
      _CoordinatorDashboardTabState();
}

class _CoordinatorDashboardTabState extends State<CoordinatorDashboardTab> {
  bool _loading = true;
  String _error = '';
  Timer? _pollTimer;
  Map<String, dynamic> _ctx = {};
  List<Map<String, dynamic>> _recentSos = [];

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
      if (!silent)
        setState(() {
          _loading = true;
          _error = '';
        });
      final results = await Future.wait([
        widget.api.get('/api/v1/coordinator/context'),
        widget.api.get('/api/v1/coordinator/sos'),
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
          _buildRecentSos(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              child: Text(
                widget.user.name.isNotEmpty ? widget.user.name[0] : '?',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${widget.user.name}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Role: ${widget.user.role.toUpperCase()}',
                    style: const TextStyle(fontSize: 12),
                  ),
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
        'Vol',
        stats['volunteers'] ?? 0,
        Icons.people_alt,
        AppColors.primaryGreen,
      ),
      ('Tasks', tasks['total'] ?? 0, Icons.assignment, Colors.blueAccent),
      ('Needs', needs['total'] ?? 0, Icons.report_problem, Colors.orange),
      ('SOS', stats['active_sos'] ?? 0, Icons.sos, AppColors.criticalRed),
      ('Missing', stats['missing'] ?? 0, Icons.person_search, Colors.purple),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final (label, value, icon, color) = item;
          return SizedBox(
            width: 80,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                child: Column(
                  children: [
                    Icon(icon, size: 20, color: color),
                    const SizedBox(height: 4),
                    Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMiniMap() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 170,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: const LatLng(28.6139, 77.2090),
            initialZoom: 11,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.sahyog_app',
            ),
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
}
