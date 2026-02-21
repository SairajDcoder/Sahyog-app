import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../theme/app_colors.dart';

class CoordinatorSosTab extends StatefulWidget {
  const CoordinatorSosTab({super.key, required this.api});

  final ApiClient api;

  @override
  State<CoordinatorSosTab> createState() => _CoordinatorSosTabState();
}

class _CoordinatorSosTabState extends State<CoordinatorSosTab> {
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

      final raw = await widget.api.get('/api/v1/coordinator/sos');
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
          const Text('Alerts within your assigned disaster zone.'),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: AppColors.criticalRed)),
          if (_alerts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No SOS alerts for your zone.'),
              ),
            )
          else
            ..._alerts.map((alert) {
              final id = (alert['id'] ?? '').toString();
              final status = (alert['status'] ?? 'triggered').toString();
              final volunteerName = (alert['volunteer_name'] ?? 'Unknown')
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
                      Text('Volunteer: $volunteerName'),
                      if (alert['media_urls'] is List &&
                          (alert['media_urls'] as List).isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('📎 Has media attachments'),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: id.isEmpty
                                ? null
                                : () => _updateStatus(id, 'in_progress'),
                            child: const Text('Acknowledge'),
                          ),
                          FilledButton.tonal(
                            onPressed: id.isEmpty
                                ? null
                                : () => _updateStatus(id, 'resolved'),
                            child: const Text('Resolve'),
                          ),
                        ],
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
