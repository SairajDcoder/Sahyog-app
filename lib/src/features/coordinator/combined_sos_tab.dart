import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/socket_service.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';

class CombinedSosTab extends StatefulWidget {
  const CombinedSosTab({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  State<CombinedSosTab> createState() => _CombinedSosTabState();
}

class _CombinedSosTabState extends State<CombinedSosTab> {
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _missingPersons = [];
  bool _loading = true;
  String _error = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
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

      final endpoint = widget.user.isCoordinator
          ? '/api/v1/coordinator/sos'
          : '/api/v1/sos';

      final results = await Future.wait([
        widget.api.get(endpoint),
        if (widget.user.isCoordinator)
          widget.api.get('/api/v1/coordinator/volunteers'),
        widget.api.get('/api/v1/missing'),
      ]);

      final list = (results[0] is List)
          ? (results[0] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      List<Map<String, dynamic>> missing = [];

      if (widget.user.isCoordinator && results.length > 2) {
        missing = (results[2] is List)
            ? (results[2] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
      } else if (results.length > 1) {
        missing = (results[1] is List)
            ? (results[1] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
      }

      if (!mounted) return;

      if (widget.user.isCoordinator ||
          widget.user.isVolunteer ||
          widget.user.isAdmin) {
        SocketService.instance.setInitialAlerts(list);
      }

      setState(() {
        _alerts = list;
        _missingPersons = missing;
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

  @override
  Widget build(BuildContext context) {
    return _buildSosTab();
  }

  Widget _buildSosTab() {
    if (_loading && _alerts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Emergency Monitor',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text('Real-time SOS and Missing reports in your area.'),
          const SizedBox(height: 20),
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.criticalRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error,
                style: const TextStyle(
                  color: AppColors.criticalRed,
                  fontSize: 13,
                ),
              ),
            ),

          // --- SECTION: SOS ALERTS ---
          Row(
            children: [
              const Icon(Icons.sos, color: AppColors.criticalRed, size: 20),
              const SizedBox(width: 8),
              Text(
                'LIVE SOS ALERTS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              if (_alerts.isNotEmpty)
                Text(
                  '${_alerts.length} Active',
                  style: const TextStyle(
                    color: AppColors.criticalRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_alerts.isEmpty)
            _buildEmptyState(
              'No active SOS alerts',
              Icons.verified_user_outlined,
            )
          else
            ..._alerts.map((alert) => _buildSosCard(alert)),

          const SizedBox(height: 32),

          // --- SECTION: MISSING PERSONS ---
          Row(
            children: [
              const Icon(
                Icons.person_search,
                color: AppColors.infoBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'MISSING PERSON REPORTS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              if (_missingPersons.isNotEmpty)
                Text(
                  '${_missingPersons.length} Reports',
                  style: const TextStyle(
                    color: AppColors.infoBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_missingPersons.isEmpty)
            _buildEmptyState(
              'No missing reports found',
              Icons.manage_search_outlined,
            )
          else
            ..._missingPersons.map((person) => _buildMissingCard(person)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Card(
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              msg,
              style: TextStyle(
                color: Colors.grey[500],
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSosCard(Map<String, dynamic> alert) {
    final status = (alert['status'] ?? 'triggered').toString();
    final isActive = status == 'triggered';
    final reporterName =
        (alert['reporter_name'] ?? alert['reporter_phone'] ?? 'Sahayanet User')
            .toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isActive ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive
              ? AppColors.criticalRed.withOpacity(0.3)
              : Colors.transparent,
          width: isActive ? 1.5 : 0,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isActive ? AppColors.criticalRed.withOpacity(0.04) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isActive
                        ? AppColors.criticalRed
                        : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    child: Icon(
                      isActive ? Icons.sos : Icons.check_circle,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isActive ? 'EMERGENCY SOS' : 'SOS Resolved',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: isActive ? AppColors.criticalRed : null,
                      ),
                    ),
                  ),
                  if (isActive)
                    _buildLiveTag()
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Reporter: $reporterName',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                alert['description'] ?? 'No description provided.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              if (alert['volunteer_name'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.handshake,
                        size: 14,
                        color: AppColors.primaryGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Assigned: ${alert['volunteer_name']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                        ),
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

  Widget _buildMissingCard(Map<String, dynamic> person) {
    final status = (person['status'] ?? 'missing').toString();
    final name = (person['name'] ?? 'Unnamed Person').toString();
    final photos = person['photo_urls'] as List?;
    final imageUrl = (photos != null && photos.isNotEmpty)
        ? photos.first.toString()
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: status == 'found'
                    ? AppColors.primaryGreen.withOpacity(0.1)
                    : AppColors.criticalRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                image: imageUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl.isEmpty
                  ? Icon(
                      status == 'found' ? Icons.verified : Icons.person_search,
                      color: status == 'found'
                          ? AppColors.primaryGreen
                          : AppColors.criticalRed,
                      size: 24,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Age: ${person['age'] ?? '??'} • ${status.toUpperCase()}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (status == 'found')
              const Icon(
                Icons.check_circle,
                color: AppColors.primaryGreen,
                size: 20,
              )
            else
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.criticalRed,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Colors.white, size: 6),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
