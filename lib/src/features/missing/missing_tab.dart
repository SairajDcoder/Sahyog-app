import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../theme/app_colors.dart';

class MissingTab extends StatefulWidget {
  const MissingTab({super.key, required this.api});

  final ApiClient api;

  @override
  State<MissingTab> createState() => _MissingTabState();
}

class _MissingTabState extends State<MissingTab> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();
  final _locService = LocationService();

  List<dynamic> _board = [];
  bool _loadingBoard = true;
  bool _submitting = false;
  double? _lat;
  double? _lng;
  String _error = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadBoard();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_submitting) _loadBoard(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _phoneCtrl.dispose();
    _photoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBoard({bool silent = false}) async {
    try {
      if (!silent) {
        setState(() {
          _loadingBoard = true;
          _error = '';
        });
      }
      final raw = await widget.api.get('/api/v1/missing');
      if (!mounted) return;
      setState(() {
        _board = raw is List ? raw : <dynamic>[];
        _loadingBoard = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBoard = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      final p = await _locService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Location unavailable: $e')));
    }
  }

  Future<void> _submitReport() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporter phone is required')),
      );
      return;
    }

    try {
      setState(() => _submitting = true);

      final body = <String, dynamic>{
        'reporter_phone': _phoneCtrl.text.trim(),
        'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()),
        'photo_urls': _photoCtrl.text.trim().isEmpty
            ? []
            : [_photoCtrl.text.trim()],
      };

      if (_lat != null && _lng != null) {
        body['last_seen_location'] = {'lat': _lat, 'lng': _lng};
      }

      await widget.api.post('/api/v1/missing', body: body);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing person report submitted.')),
      );

      _nameCtrl.clear();
      _ageCtrl.clear();
      _photoCtrl.clear();
      _lat = null;
      _lng = null;

      await _loadBoard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _markFound(String missingId) async {
    final noteCtrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Missing Report'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Closure description',
            hintText: 'Add found details...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, noteCtrl.text.trim()),
            child: const Text('Mark Found'),
          ),
        ],
      ),
    );
    noteCtrl.dispose();

    if (note == null) return;

    try {
      await widget.api.patch(
        '/api/v1/missing/$missingId/found',
        body: {'description': note},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing report closed as found.')),
      );
      await _loadBoard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Close failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const TabBar(
            tabs: [
              Tab(text: 'Missing Board'),
              Tab(text: 'Report Missing'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: _loadBoard,
                  child: _loadingBoard
                      ? const Center(child: CircularProgressIndicator())
                      : _buildBoard(),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildForm(),
                ),
              ],
            ),
          ),
        ],
      ),
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
            padding: EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No missing-person reports found.'),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _board.length,
      itemBuilder: (context, index) {
        final item = _board[index] as Map<String, dynamic>;
        final status = (item['status'] ?? 'missing').toString();
        final name = (item['name'] ?? 'Unnamed').toString();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: status == 'found'
                    ? AppColors.primaryGreen.withValues(alpha: 0.15)
                    : AppColors.criticalRed.withValues(alpha: 0.15),
                child: Icon(
                  status == 'found' ? Icons.verified : Icons.person_search,
                  color: status == 'found'
                      ? AppColors.primaryGreen
                      : AppColors.criticalRed,
                ),
              ),
              title: Text(name),
              subtitle: Text(
                'Age: ${item['age'] ?? 'Unknown'} • Status: $status',
              ),
              trailing: status == 'found'
                  ? const Chip(label: Text('FOUND'))
                  : FilledButton.tonal(
                      onPressed: () =>
                          _markFound((item['id'] ?? '').toString()),
                      child: const Text('Mark Found'),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Report Missing Person',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Reporter Phone *',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Missing Person Name',
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ageCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Approximate Age',
            prefixIcon: Icon(Icons.cake_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _photoCtrl,
          decoration: const InputDecoration(
            labelText: 'Photo URL (Optional)',
            prefixIcon: Icon(Icons.photo_camera_back_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _useCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Use Current Location'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _lat == null || _lng == null
                    ? 'Location not selected'
                    : '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submitReport,
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit Report'),
          ),
        ),
      ],
    );
  }
}
