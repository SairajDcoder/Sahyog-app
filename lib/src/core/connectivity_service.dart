import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_client.dart';
import 'database_helper.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._internal();

  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  ApiClient? _api;

  void initialize(ApiClient api) {
    _api = api;
    // Listen to network changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectionChange,
    );
  }

  void dispose() {
    _subscription?.cancel();
  }

  Future<void> _handleConnectionChange(List<ConnectivityResult> results) async {
    // If we have any connection (WiFi, Mobile, etc), try syncing
    if (results.any((r) => r != ConnectivityResult.none)) {
      await syncOfflineIncidents();
    }
  }

  /// Manually callable to push all pending SQLite SOS incidents to the backend
  Future<void> syncOfflineIncidents() async {
    if (_api == null) return;

    final db = DatabaseHelper.instance;
    final pending = await db.getPendingIncidents();

    if (pending.isEmpty) return;

    for (var incident in pending) {
      try {
        // Construct the payload for the backend
        final body = <String, dynamic>{};
        if (incident['location_lat'] != null &&
            incident['location_lng'] != null) {
          body['location'] = {
            'lat': incident['location_lat'],
            'lng': incident['location_lng'],
          };
        }

        // Push to server
        await _api!.post('/api/v1/sos', body: body);

        // Mark as synced locally
        await db.markIncidentSynced(incident['id'] as int);
      } catch (e) {
        // If it fails (e.g., server down or token expired), we leave it pending to try again later
        print('Failed to sync offline SOS incident ${incident['id']}: $e');
      }
    }
  }
}
