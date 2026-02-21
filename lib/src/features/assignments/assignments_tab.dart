import 'dart:async';

import 'package:flutter/material.dart';

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
  final _taskTitleCtrl = TextEditingController();
  final _taskTypeCtrl = TextEditingController(text: 'field_support');
  final _taskDescCtrl = TextEditingController();

  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _pendingTasks = [];
  List<Map<String, dynamic>> _taskHistory = [];

  bool _loading = true;
  bool _creating = false;
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
    _taskTitleCtrl.dispose();
    _taskTypeCtrl.dispose();
    _taskDescCtrl.dispose();
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
        final results = await Future.wait([
          widget.api.get('/api/v1/volunteer-assignments/mine'),
          widget.api.get('/api/v1/tasks/pending'),
          widget.api.get('/api/v1/tasks/history'),
        ]);

        _assignments = results[0] is List
            ? (results[0] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        _pendingTasks = results[1] is List
            ? (results[1] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        _taskHistory = results[2] is List
            ? (results[2] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
      } else if (widget.user.isCoordinator) {
        final raw = await widget.api.get('/api/v1/coordinator/needs');
        _assignments = raw is List
            ? raw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
      } else {
        _assignments = [];
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

  Future<void> _createVolunteerTask() async {
    if (_taskTitleCtrl.text.trim().isEmpty ||
        _taskTypeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task title and type are required.')),
      );
      return;
    }

    try {
      setState(() => _creating = true);
      await widget.api.post(
        '/api/v1/tasks',
        body: {
          'title': _taskTitleCtrl.text.trim(),
          'type': _taskTypeCtrl.text.trim(),
          'description': _taskDescCtrl.text.trim().isEmpty
              ? null
              : _taskDescCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      _taskTitleCtrl.clear();
      _taskDescCtrl.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task created.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Task creation failed: $e')));
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Task updated: $status')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _voteTaskCompletion(String taskId, String vote) async {
    try {
      final raw = await widget.api.post(
        '/api/v1/tasks/$taskId/vote-completion',
        body: {'vote': vote, 'note': 'Mobile volunteer vote'},
      );
      final summary =
          (raw is Map<String, dynamic> &&
              raw['summary'] is Map<String, dynamic>)
          ? raw['summary'] as Map<String, dynamic>
          : <String, dynamic>{};

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Vote recorded. ${summary['completed_votes'] ?? 0}/${summary['required_votes'] ?? 0} completion votes.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Vote failed: $e')));
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
                ? 'Volunteer Operations'
                : 'Coordinator Needs Dashboard',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: AppColors.criticalRed)),

          if (widget.user.isVolunteer) ...[
            _buildVolunteerTaskCreateCard(),
            const SizedBox(height: 12),
            _buildVolunteerAssignments(),
            const SizedBox(height: 12),
            _buildPendingTasks(),
            const SizedBox(height: 12),
            _buildTaskHistory(),
          ] else ...[
            _buildCoordinatorNeeds(),
          ],
        ],
      ),
    );
  }

  Widget _buildVolunteerTaskCreateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Task',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _taskTitleCtrl,
              decoration: const InputDecoration(
                labelText: 'Task Title',
                prefixIcon: Icon(Icons.task_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _taskTypeCtrl,
              decoration: const InputDecoration(
                labelText: 'Task Type',
                prefixIcon: Icon(Icons.category_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _taskDescCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _creating ? null : _createVolunteerTask,
              icon: const Icon(Icons.add_task),
              label: const Text('Create Task'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolunteerAssignments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Disaster Assignments',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_assignments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('No disaster assignments.'),
            ),
          )
        else
          ..._assignments.map((item) {
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
          }),
      ],
    );
  }

  Widget _buildPendingTasks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Active Tasks',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_pendingTasks.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('No pending tasks.'),
            ),
          )
        else
          ..._pendingTasks.map((task) {
            final id = (task['id'] ?? '').toString();
            final status = (task['status'] ?? 'pending').toString();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (task['title'] ?? task['type'] ?? 'Task').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Status: $status'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: id.isEmpty
                              ? null
                              : () => _updateTaskStatus(id, 'in_progress'),
                          child: const Text('Start'),
                        ),
                        FilledButton.tonal(
                          onPressed: id.isEmpty
                              ? null
                              : () => _updateTaskStatus(id, 'completed'),
                          child: const Text('Close Task'),
                        ),
                        TextButton(
                          onPressed: id.isEmpty
                              ? null
                              : () => _voteTaskCompletion(id, 'completed'),
                          child: const Text('Vote Complete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTaskHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Task History',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_taskHistory.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('No completed history yet.'),
            ),
          )
        else
          ..._taskHistory.take(20).map((task) {
            final title = (task['title'] ?? task['type'] ?? 'Task').toString();
            final completedAt = (task['completed_at'] ?? '').toString();
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.check),
                ),
                title: Text(title),
                subtitle: Text(completedAt.isEmpty ? 'Completed' : completedAt),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCoordinatorNeeds() {
    if (_assignments.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No records found.'),
        ),
      );
    }

    return Column(
      children: _assignments.map((item) {
        final needId = (item['id'] ?? '').toString();
        return Card(
          child: ListTile(
            title: Text((item['type'] ?? 'Need').toString()),
            subtitle: Text(
              'Urgency: ${item['urgency'] ?? '-'} • Status: ${item['status'] ?? '-'}',
            ),
            trailing: FilledButton.tonal(
              onPressed: needId.isEmpty ? null : () => _resolveNeed(needId),
              child: const Text('Resolve'),
            ),
          ),
        );
      }).toList(),
    );
  }
}
