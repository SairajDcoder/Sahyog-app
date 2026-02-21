import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';
import '../../core/database_helper.dart';
import '../../core/connectivity_service.dart';

class UserHomeTab extends StatefulWidget {
  const UserHomeTab({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  State<UserHomeTab> createState() => _UserHomeTabState();
}

class _UserHomeTabState extends State<UserHomeTab>
    with AutomaticKeepAliveClientMixin {
  final _locationService = LocationService();
  final MapController _miniMapController = MapController();

  Position? _position;
  bool _loading = true;
  List<Map<String, dynamic>> _alerts = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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
        });
      }

      Position? pos;
      try {
        pos = await _locationService.getCurrentPosition().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {}

      final disastersRaw = await widget.api.get('/api/v1/disasters');
      final disasters = (disastersRaw is List)
          ? disastersRaw.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _position = pos;
        _alerts = disasters;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _triggerSOS() async {
    // Save to local SQLite immediately
    final incident = {
      'reporter_id': widget.user.id,
      'location_lat': _position?.latitude,
      'location_lng': _position?.longitude,
      'captured_at': DateTime.now().toIso8601String(),
    };

    await DatabaseHelper.instance.insertIncident(incident);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS Activated! Saved locally.'),
          backgroundColor: AppColors.criticalRed,
          duration: Duration(seconds: 2),
        ),
      );
    }

    // Try background sync
    await ConnectivityService.instance.syncOfflineIncidents();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _UserStatusBanner(user: widget.user),
          const SizedBox(height: 16),
          _buildEmergencySOSButton(),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(height: 220, child: _buildMiniMap()),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(
                Icons.emergency_share_outlined,
                color: AppColors.criticalRed,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Recent Disaster Alerts',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_alerts.isEmpty)
            _EmptyAlertsState()
          else
            ..._alerts.map(
              (alert) => _AlertCard(alert: alert, api: widget.api),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEmergencySOSButton() {
    return InkWell(
      onTap: _triggerSOS,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.criticalRed,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.criticalRed.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emergency, color: Colors.white, size: 36),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'TRIGGER SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap to request immediate help',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMap() {
    LatLng center = const LatLng(18.5204, 73.8567);
    if (_position != null) {
      center = LatLng(_position!.latitude, _position!.longitude);
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _miniMapController,
          options: MapOptions(initialCenter: center, initialZoom: 13),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.sahyog_app',
            ),
            if (_position != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_pin_circle,
                          color: AppColors.primaryGreen,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.my_location,
                  size: 14,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Live View',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UserStatusBanner extends StatelessWidget {
  const _UserStatusBanner({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryGreen.withOpacity(0.1), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primaryGreen.withOpacity(0.2),
            child: const Icon(
              Icons.verified_user,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${user.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Stay safe. Monitor active alerts below.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.api});
  final Map<String, dynamic> alert;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final severity = (alert['severity'] ?? 0).toInt();
    final isCritical = severity >= 4;
    final color = isCritical ? AppColors.criticalRed : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => AlertDetailPage(alert: alert, api: api),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (alert['name'] ?? 'Disaster Alert').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (alert['type'] ?? 'Unknown Type')
                          .toString()
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAlertsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.shield_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'No active alerts in your area',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class AlertDetailPage extends StatelessWidget {
  const AlertDetailPage({super.key, required this.alert, required this.api});
  final Map<String, dynamic> alert;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alert Details')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            (alert['name'] ?? 'Disaster Update').toString(),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Tag(
                label: (alert['type'] ?? 'Disaster').toString().toUpperCase(),
                color: AppColors.primaryGreen,
              ),
              const SizedBox(width: 8),
              _Tag(
                label: 'SEVERITY: ${alert['severity'] ?? 'N/A'}',
                color: AppColors.criticalRed,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Description',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          Text(
            (alert['description'] ??
                    'No detailed description available for this alert at this time. Please follow local news and official guidance.')
                .toString(),
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Affected Area',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 250,
              color: Colors.grey[100],
              child: const Center(child: Text('Map View of Affected Area')),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
