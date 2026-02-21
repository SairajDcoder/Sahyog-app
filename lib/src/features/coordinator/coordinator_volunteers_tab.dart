import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../theme/app_colors.dart';

class CoordinatorVolunteersTab extends StatefulWidget {
  const CoordinatorVolunteersTab({super.key, required this.api});

  final ApiClient api;

  @override
  State<CoordinatorVolunteersTab> createState() =>
      _CoordinatorVolunteersTabState();
}

class _CoordinatorVolunteersTabState extends State<CoordinatorVolunteersTab> {
  final _needIdController = TextEditingController();
  final _volunteerIdController = TextEditingController();

  List<Map<String, dynamic>> _needs = [];
  List<String> _derivedVolunteerIds = [];
  bool _loading = true;
  bool _submitting = false;
  String _error = '';
  Timer? _pollTimer;

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
    _needIdController.dispose();
    _volunteerIdController.dispose();
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

      final needsRaw = await widget.api.get('/api/v1/needs');
      final needs = (needsRaw is List)
          ? needsRaw.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      final volunteerIds = <String>{};
      for (final need in needs) {
        final id = need['assigned_volunteer_id']?.toString();
        if (id != null && id.isNotEmpty) volunteerIds.add(id);
      }

      if (!mounted) return;
      setState(() {
        _needs = needs;
        _derivedVolunteerIds = volunteerIds.toList()..sort();
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

  Future<void> _assignVolunteer() async {
    final needId = _needIdController.text.trim();
    final volunteerId = _volunteerIdController.text.trim();

    if (needId.isEmpty || volunteerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need ID and Volunteer ID are required.')),
      );
      return;
    }

    try {
      setState(() => _submitting = true);
      await widget.api.patch(
        '/api/v1/needs/$needId/assign',
        body: {'volunteer_id': volunteerId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Volunteer assigned.')));
      _needIdController.clear();
      _volunteerIdController.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Assignment failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Volunteer Management',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Live operational view from coordinator-accessible endpoints. Admin-only volunteer endpoints are not exposed to coordinator role.',
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_error, style: const TextStyle(color: AppColors.criticalRed)),
          ],
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assign Volunteer To Need',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _needIdController,
                    decoration: const InputDecoration(
                      labelText: 'Need ID',
                      prefixIcon: Icon(Icons.report),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _volunteerIdController,
                    decoration: const InputDecoration(
                      labelText: 'Volunteer ID',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _assignVolunteer,
                    icon: const Icon(Icons.assignment_ind_outlined),
                    label: const Text('Assign'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Active Volunteers (Derived)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_derivedVolunteerIds.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'No assigned volunteers found from current need records.',
                ),
              ),
            )
          else
            ..._derivedVolunteerIds.map(
              (id) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.volunteer_activism_outlined),
                  ),
                  title: Text('Volunteer $id'),
                  subtitle: const Text('Status source: assigned needs'),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            'Need Assignments Snapshot',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._needs.take(10).map((need) {
            final status = (need['status'] ?? 'unassigned').toString();
            final volunteerId = (need['assigned_volunteer_id'] ?? '-')
                .toString();
            return Card(
              child: ListTile(
                title: Text((need['type'] ?? 'Need').toString()),
                subtitle: Text('Volunteer: $volunteerId'),
                trailing: Chip(label: Text(status.toUpperCase())),
              ),
            );
          }),
        ],
      ),
    );
  }
}
