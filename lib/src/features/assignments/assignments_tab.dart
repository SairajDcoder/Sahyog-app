import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../theme/app_colors.dart';

class AssignmentsTab extends StatefulWidget {
  const AssignmentsTab({super.key, required this.api, required this.user});

  final ApiClient api;
  final AppUser user;

  @override
  State<AssignmentsTab> createState() => _AssignmentsTabState();
}

class _AssignmentsTabState extends State<AssignmentsTab> {
  List<dynamic> _items = [];
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

      if (widget.user.isVolunteer) {
        final raw = await widget.api.get('/api/v1/volunteer-assignments/mine');
        _items = raw is List ? raw : <dynamic>[];
      } else if (widget.user.isCoordinator) {
        final raw = await widget.api.get('/api/v1/needs');
        _items = raw is List ? raw : <dynamic>[];
      } else {
        _items = [];
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _respond(String assignmentId, String status) async {
    try {
      await widget.api.post(
        '/api/v1/volunteer-assignments/$assignmentId/respond',
        body: {'status': status},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Assignment $status')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _resolveNeed(String id) async {
    try {
      await widget.api.patch('/api/v1/needs/$id/resolve');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Need marked as resolved')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Resolve failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!widget.user.isVolunteer && !widget.user.isCoordinator) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Assignments are available for volunteer/coordinator roles.',
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.user.isVolunteer
                ? 'Disaster Assignments Dashboard'
                : 'Coordinator Needs Dashboard',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: AppColors.criticalRed)),
          if (_items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No records found.'),
              ),
            )
          else
            ..._items.map((raw) {
              final item = raw as Map<String, dynamic>;
              if (widget.user.isVolunteer) {
                final status = (item['status'] ?? 'pending').toString();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (item['disaster_name'] ?? 'Disaster Assignment')
                              .toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Severity: ${item['disaster_severity'] ?? '-'}'),
                        Text('Coordinator: ${item['coordinator_name'] ?? '-'}'),
                        Text('Contact: ${item['coordinator_phone'] ?? '-'}'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(label: Text(status.toUpperCase())),
                            if (status == 'pending')
                              FilledButton(
                                onPressed: () => _respond(
                                  (item['id'] ?? '').toString(),
                                  'accepted',
                                ),
                                child: const Text('Accept'),
                              ),
                            if (status == 'pending')
                              OutlinedButton(
                                onPressed: () => _respond(
                                  (item['id'] ?? '').toString(),
                                  'rejected',
                                ),
                                child: const Text('Reject'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              final needId = (item['id'] ?? '').toString();
              return Card(
                child: ListTile(
                  title: Text((item['type'] ?? 'Need').toString()),
                  subtitle: Text(
                    'Urgency: ${item['urgency'] ?? '-'} • Status: ${item['status'] ?? '-'}',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: needId.isEmpty
                        ? null
                        : () => _resolveNeed(needId),
                    child: const Text('Resolve'),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
