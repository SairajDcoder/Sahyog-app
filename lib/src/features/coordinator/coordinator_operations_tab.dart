import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../theme/app_colors.dart';

/// Operations tab: Volunteers / Tasks / Needs as segmented top tabs.
class CoordinatorOperationsTab extends StatefulWidget {
  const CoordinatorOperationsTab({super.key, required this.api});

  final ApiClient api;

  @override
  State<CoordinatorOperationsTab> createState() =>
      _CoordinatorOperationsTabState();
}

class _CoordinatorOperationsTabState extends State<CoordinatorOperationsTab> {
  List<Map<String, dynamic>> _volunteers = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _needs = [];
  bool _loading = true;
  String _error = '';
  Timer? _pollTimer;

  // Task creation
  final _titleCtrl = TextEditingController();
  final _typeCtrl = TextEditingController(text: 'rescue');
  final _descCtrl = TextEditingController();
  List<Map<String, dynamic>> _selectedVolunteers = [];
  bool _creating = false;

  // Needs filter
  String _needsFilter = 'all';

  // Expanded volunteer cards
  final Set<String> _expandedVolunteers = {};

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
    _titleCtrl.dispose();
    _typeCtrl.dispose();
    _descCtrl.dispose();
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
        widget.api.get('/api/v1/coordinator/volunteers'),
        widget.api.get('/api/v1/coordinator/tasks'),
        widget.api.get('/api/v1/coordinator/needs'),
      ]);
      if (!mounted) return;
      setState(() {
        _volunteers = _toList(results[0]);
        _tasks = _toList(results[1]);
        _needs = _toList(results[2]);
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

  List<Map<String, dynamic>> _toList(dynamic raw) =>
      (raw is List) ? raw.cast<Map<String, dynamic>>() : [];

  // ── Volunteer Selection Panel ──────────────────────────────────────
  void _openVolunteerPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final selectedIds = _selectedVolunteers
            .map((v) => v['id'].toString())
            .toSet();
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            'Select Volunteers',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _volunteers.length,
                        itemBuilder: (ctx, i) {
                          final v = _volunteers[i];
                          final id = v['id'].toString();
                          final name = (v['full_name'] ?? 'Unnamed').toString();
                          final isSelected = selectedIds.contains(id);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(name),
                            subtitle: Text(
                              (v['email'] ?? '').toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                            secondary: CircleAvatar(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              child: Text(name.isNotEmpty ? name[0] : '?'),
                            ),
                            onChanged: (checked) {
                              setSheetState(() {
                                if (checked == true) {
                                  selectedIds.add(id);
                                } else {
                                  selectedIds.remove(id);
                                }
                              });
                              setState(() {
                                if (checked == true) {
                                  _selectedVolunteers.add(v);
                                } else {
                                  _selectedVolunteers.removeWhere(
                                    (sv) => sv['id'].toString() == id,
                                  );
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Task CRUD ──────────────────────────────────────────────────────
  Future<void> _createTask() async {
    if (_titleCtrl.text.trim().isEmpty || _typeCtrl.text.trim().isEmpty) {
      _snack('Title and type are required.');
      return;
    }
    try {
      setState(() => _creating = true);
      // Create one task per selected volunteer (or one unassigned task)
      if (_selectedVolunteers.isEmpty) {
        await widget.api.post(
          '/api/v1/coordinator/tasks',
          body: {
            'title': _titleCtrl.text.trim(),
            'type': _typeCtrl.text.trim(),
            'description': _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
          },
        );
      } else {
        for (final v in _selectedVolunteers) {
          await widget.api.post(
            '/api/v1/coordinator/tasks',
            body: {
              'title': _titleCtrl.text.trim(),
              'type': _typeCtrl.text.trim(),
              'description': _descCtrl.text.trim().isEmpty
                  ? null
                  : _descCtrl.text.trim(),
              'volunteer_id': v['id'].toString(),
            },
          );
        }
      }
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() => _selectedVolunteers = []);
      _snack('Task created.');
      await _load();
    } catch (e) {
      _snack('Create failed: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _updateTaskStatus(String taskId, String status) async {
    try {
      await widget.api.patch(
        '/api/v1/tasks/$taskId/status',
        body: {'status': status},
      );
      _snack('Task → $status');
      await _load();
    } catch (e) {
      _snack('Update failed: $e');
    }
  }

  Future<void> _deleteTask(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.delete('/api/v1/coordinator/tasks/$taskId');
      _snack('Task deleted.');
      await _load();
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Volunteers'),
              Tab(text: 'Tasks'),
              Tab(text: 'Needs'),
            ],
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error,
                style: const TextStyle(color: AppColors.criticalRed),
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [
                _buildVolunteersTab(),
                _buildTasksTab(),
                _buildNeedsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Volunteers ─────────────────────────────────────────────────────
  Widget _buildVolunteersTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: _volunteers.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No volunteers found.')),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _volunteers.length,
              itemBuilder: (context, index) {
                final v = _volunteers[index];
                final id = v['id'].toString();
                final name = (v['full_name'] ?? 'Unnamed').toString();
                final email = (v['email'] ?? '').toString();
                final verified = v['is_verified'] == true;
                final available = v['is_available'] == true;
                final expanded = _expandedVolunteers.contains(id);
                final assignedTasks = _tasks
                    .where((t) => t['volunteer_id']?.toString() == id)
                    .toList();

                return Card(
                  child: InkWell(
                    onTap: () => setState(() {
                      expanded
                          ? _expandedVolunteers.remove(id)
                          : _expandedVolunteers.add(id);
                    }),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      email,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (verified)
                                const Icon(
                                  Icons.verified,
                                  color: AppColors.primaryGreen,
                                  size: 18,
                                ),
                              const SizedBox(width: 4),
                              Chip(
                                label: Text(
                                  available ? 'ONLINE' : 'OFFLINE',
                                  style: const TextStyle(fontSize: 9),
                                ),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                backgroundColor: available
                                    ? Colors.green.shade50
                                    : Colors.grey.shade200,
                              ),
                              Icon(
                                expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                              ),
                            ],
                          ),
                          if (expanded) ...[
                            const Divider(height: 16),
                            Text(
                              'Assigned Tasks (${assignedTasks.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (assignedTasks.isEmpty)
                              const Text(
                                'No tasks assigned.',
                                style: TextStyle(fontSize: 12),
                              )
                            else
                              ...assignedTasks.map(
                                (t) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.circle,
                                        size: 6,
                                        color: AppColors.primaryGreen,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${t['title'] ?? t['type']} — ${(t['status'] ?? 'pending').toString().toUpperCase()}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ── Tasks ──────────────────────────────────────────────────────────
  Widget _buildTasksTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Create Task form
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Task',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.task_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _typeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Volunteer selection button + chips
                  OutlinedButton.icon(
                    onPressed: _openVolunteerPanel,
                    icon: const Icon(Icons.person_add_outlined),
                    label: Text(
                      _selectedVolunteers.isEmpty
                          ? 'Select Volunteers'
                          : '${_selectedVolunteers.length} selected',
                    ),
                  ),
                  if (_selectedVolunteers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _selectedVolunteers.map((v) {
                          return Chip(
                            label: Text(
                              (v['full_name'] ?? 'Unnamed').toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onDeleted: () {
                              setState(() {
                                _selectedVolunteers.removeWhere(
                                  (sv) => sv['id'] == v['id'],
                                );
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _creating ? null : _createTask,
                    icon: const Icon(Icons.add_task),
                    label: const Text('Create Task'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Task list
          if (_tasks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No tasks yet.'),
              ),
            )
          else
            ..._tasks.map(_buildTaskCard),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final id = (task['id'] ?? '').toString();
    final status = (task['status'] ?? 'pending').toString();
    final volunteerName = (task['volunteer_name'] ?? 'Unassigned').toString();
    final desc = (task['description'] ?? '').toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (task['title'] ?? task['type'] ?? 'Task').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(
                    status.toUpperCase(),
                    style: const TextStyle(fontSize: 10),
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Volunteer: $volunteerName',
              style: const TextStyle(fontSize: 12),
            ),
            if (desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(desc, style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: id.isEmpty
                      ? null
                      : () => _updateTaskStatus(id, 'in_progress'),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Start'),
                ),
                FilledButton.tonal(
                  onPressed: id.isEmpty
                      ? null
                      : () => _updateTaskStatus(id, 'completed'),
                  child: const Text('Complete'),
                ),
                IconButton(
                  onPressed: id.isEmpty ? null : () => _deleteTask(id),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.criticalRed,
                    size: 20,
                  ),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Needs (read-only) ──────────────────────────────────────────────
  Widget _buildNeedsTab() {
    final filtered = _needsFilter == 'all'
        ? _needs
        : _needs
              .where((n) => (n['status'] ?? '').toString() == _needsFilter)
              .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            children: ['all', 'unassigned', 'assigned', 'resolved'].map((s) {
              return ChoiceChip(
                label: Text(s.toUpperCase()),
                selected: _needsFilter == s,
                onSelected: (_) => setState(() => _needsFilter = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No needs for this filter.'),
              ),
            )
          else
            ...filtered.map((need) {
              final status = (need['status'] ?? 'unassigned').toString();
              final volName = (need['volunteer_name'] ?? 'Unassigned')
                  .toString();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (need['type'] ?? 'Need').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reporter: ${need['reporter_name'] ?? 'Unknown'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Urgency: ${need['urgency'] ?? 'medium'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Volunteer: $volName',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Chip(
                        label: Text(
                          status.toUpperCase(),
                          style: const TextStyle(fontSize: 10),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
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
