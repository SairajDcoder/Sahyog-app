import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';
import '../missing/missing_tab.dart';

class CombinedSosTab extends StatefulWidget {
  const CombinedSosTab({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  State<CombinedSosTab> createState() => _CombinedSosTabState();
}

class _CombinedSosTabState extends State<CombinedSosTab> {
  List<Map<String, dynamic>> _alerts = [];
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

      // If coordinator, use the dedicated coordinator endpoint.
      // Else use the general SOS endpoint which honors user/volunteer visibility.
      final endpoint = widget.user.isCoordinator
          ? '/api/v1/coordinator/sos'
          : '/api/v1/sos';

      final raw = await widget.api.get(endpoint);
      final list = (raw is List)
          ? raw.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _alerts = list;
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

  Future<void> _updateStatus(String id, String status) async {
    try {
      await widget.api.patch(
        '/api/v1/sos/$id/status',
        body: {'status': status},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('SOS updated: $status')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'SOS Alerts'),
              Tab(text: 'Missing Persons'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSosTab(),
                MissingTab(api: widget.api),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'SOS Monitoring',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('SOS alerts within your area.'),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: AppColors.criticalRed)),
          if (_alerts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No SOS alerts found.'),
              ),
            )
          else
            ..._alerts.map((alert) {
              final id = (alert['id'] ?? '').toString();
              final status = (alert['status'] ?? 'triggered').toString();
              final reporterName =
                  (alert['reporter_name'] ??
                          alert['reporter_phone'] ??
                          'Sahayanet User')
                      .toString();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.criticalRed,
                            foregroundColor: Colors.white,
                            child: Icon(Icons.sos),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'SOS Alert',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Chip(label: Text(status.toUpperCase())),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Reporter: $reporterName'),
                      if (alert['media_urls'] is List &&
                          (alert['media_urls'] as List).isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('📎 Has media attachments'),
                        ),
                      const SizedBox(height: 8),
                      if (widget.user.isCoordinator)
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: id.isEmpty
                                  ? null
                                  : () => _updateStatus(id, 'acknowledged'),
                              child: const Text('Acknowledge'),
                            ),
                            FilledButton.tonal(
                              onPressed: id.isEmpty
                                  ? null
                                  : () => _updateStatus(id, 'resolved'),
                              child: const Text('Resolve'),
                            ),
                          ],
                        )
                      else if (status == 'triggered')
                        OutlinedButton.icon(
                          onPressed: () => _updateStatus(id, 'cancelled'),
                          icon: const Icon(Icons.cancel, size: 18),
                          label: const Text('Cancel Request'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
