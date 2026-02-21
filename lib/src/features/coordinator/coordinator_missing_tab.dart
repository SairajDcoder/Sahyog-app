import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../theme/app_colors.dart';

/// Coordinator Missing Persons — single tab (no report form).
/// Shows all missing persons with sorting and Mark Found.
class CoordinatorMissingTab extends StatefulWidget {
  const CoordinatorMissingTab({super.key, required this.api});

  final ApiClient api;

  @override
  State<CoordinatorMissingTab> createState() => _CoordinatorMissingTabState();
}

class _CoordinatorMissingTabState extends State<CoordinatorMissingTab> {
  List<Map<String, dynamic>> _board = [];
  bool _loading = true;
  String _error = '';
  Timer? _pollTimer;

  String _sortBy = 'created_at';
  String _sortOrder = 'desc';

  @override
  void initState() {
    super.initState();
    _loadBoard();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadBoard(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBoard({bool silent = false}) async {
    try {
      if (!silent)
        setState(() {
          _loading = true;
          _error = '';
        });
      final raw = await widget.api.get(
        '/api/v1/coordinator/missing',
        query: {'sort': _sortBy, 'order': _sortOrder},
      );
      if (!mounted) return;
      setState(() {
        _board = (raw is List)
            ? raw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
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

  Future<void> _markFound(String id) async {
    try {
      await widget.api.patch('/api/v1/coordinator/missing/$id/found');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as found.')));
      await _loadBoard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sort controls
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text('Sort by:', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _sortBy,
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'created_at', child: Text('Date')),
                  DropdownMenuItem(value: 'name', child: Text('Name')),
                  DropdownMenuItem(value: 'status', child: Text('Status')),
                  DropdownMenuItem(value: 'age', child: Text('Age')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _sortBy = val);
                    _loadBoard();
                  }
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  _sortOrder == 'desc'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 18,
                ),
                tooltip: _sortOrder == 'desc' ? 'Newest first' : 'Oldest first',
                onPressed: () {
                  setState(
                    () => _sortOrder = _sortOrder == 'desc' ? 'asc' : 'desc',
                  );
                  _loadBoard();
                },
              ),
              const Spacer(),
              Text(
                '${_board.length} reports',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Board
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _loadBoard, child: _buildBoard()),
        ),
      ],
    );
  }

  Widget _buildBoard() {
    if (_error.isNotEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error,
              style: const TextStyle(color: AppColors.criticalRed),
            ),
          ),
        ],
      );
    }
    if (_board.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No missing person reports.')),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _board.length,
      itemBuilder: (context, index) {
        final item = _board[index];
        final status = (item['status'] ?? 'missing').toString();
        final name = (item['name'] ?? 'Unnamed').toString();
        final age = item['age']?.toString() ?? 'Unknown';
        final id = (item['id'] ?? '').toString();
        final isFound = status == 'found';
        final phone = (item['reporter_phone'] ?? '').toString();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isFound
                      ? AppColors.primaryGreen.withValues(alpha: 0.15)
                      : AppColors.criticalRed.withValues(alpha: 0.15),
                  child: Icon(
                    isFound ? Icons.verified : Icons.person_search,
                    color: isFound
                        ? AppColors.primaryGreen
                        : AppColors.criticalRed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Age: $age • Phone: $phone',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Status: ${status.toUpperCase()}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!isFound && id.isNotEmpty)
                  FilledButton.tonal(
                    onPressed: () => _markFound(id),
                    child: const Text('Found', style: TextStyle(fontSize: 12)),
                  )
                else if (isFound)
                  const Chip(
                    label: Text('FOUND', style: TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
