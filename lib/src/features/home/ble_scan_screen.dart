import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/ble_payload_codec.dart';
import '../../core/ble_scanner_service.dart';
import '../../core/database_helper.dart';
import '../../core/sos_state_machine.dart';
import '../../theme/app_colors.dart';

class BleScanScreen extends StatefulWidget {
  final ApiClient api;

  const BleScanScreen({super.key, required this.api});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  bool _isScanning = false;
  bool _done = false;

  /// All decoded Sahyog beacons discovered during this scan session
  final Map<int, _FoundVictim> _victims = {}; // uuidHash → victim

  /// Tracks which beacons we've already responded to
  final Set<int> _responded = {};

  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    // Listen to the raw notifier from the service -- this bypasses dedup
    BleScannerService.instance.rawSosBeaconNotifier.addListener(
      _onBeaconDetected,
    );
  }

  @override
  void dispose() {
    BleScannerService.instance.rawSosBeaconNotifier.removeListener(
      _onBeaconDetected,
    );
    _stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _done = false;
      _victims.clear();
    });

    // Use our battle-tested service instead of raw local scan
    await BleScannerService.instance.startScanning();

    // Auto-stop after 20 seconds
    _scanTimer = Timer(const Duration(seconds: 20), _stopScan);
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await BleScannerService.instance.stopScanning();
    if (mounted) {
      setState(() {
        _isScanning = false;
        _done = true;
      });
    }
  }

  void _onBeaconDetected() {
    final beacon = BleScannerService.instance.rawSosBeaconNotifier.value;
    if (beacon == null || !beacon.isSos) return;

    // Get latest distance for this hash from service
    final distanceLabel =
        BleScannerService.instance.distanceNotifier.value[beacon.uuidHash] ??
        'Nearby';

    if (mounted) {
      setState(() {
        _victims[beacon.uuidHash] = _FoundVictim(
          beacon: beacon,
          rssi:
              0, // In this mode, we get RSSI via the service distance notifier
          distance: distanceLabel,
        );
      });
    }
  }

  Future<void> _relayAndAck(_FoundVictim victim) async {
    if (_responded.contains(victim.beacon.uuidHash)) return;
    setState(() => _responded.add(victim.beacon.uuidHash));

    final beacon = victim.beacon;

    // 1. Upload SOS to backend on behalf of the victim
    bool uploaded = false;
    try {
      final body = <String, dynamic>{
        'type': beacon.incidentTypeString,
        'lat': beacon.lat,
        'lng': beacon.lng,
        'client_uuid': 'relay_${beacon.uuidHash}',
        'source': 'mesh_relay',
        'hop_count': 1,
      };
      final res = await widget.api.post('/api/v1/sos', body: body);
      if (res is Map<String, dynamic> && res['id'] != null) {
        // Save relay record
        final relay = SosIncident(
          reporterId: 'relay',
          lat: beacon.lat,
          lng: beacon.lng,
          type: beacon.incidentTypeString,
          status: SosStatus.activeOnline,
          source: 'mesh_relay',
          hopCount: 1,
          uuidHash: beacon.uuidHash,
          backendId: res['id'].toString(),
        );
        await DatabaseHelper.instance.saveMeshRelay(relay);
        await DatabaseHelper.instance.atomicUpdateIncident(
          relay.uuid,
          status: SosStatus.activeOnline,
          isSynced: true,
          backendId: res['id'].toString(),
          deliveryChannel: 'mesh_relay',
        );
        uploaded = true;
      }
    } catch (e) {
      SosLog.warn('BLE_SCAN_SCREEN', 'Relay upload failed: $e');
    }

    // 2. Send ACK beacon so victim's phone knows help is coming
    await BleScannerService.instance.sendAckBeacon(beacon.uuidHash);

    if (mounted) {
      _showSnack(
        uploaded
            ? '✅ SOS relayed to server! ACK sent to victim via BLE.'
            : '⚠️ ACK sent. Server upload failed — will retry later.',
        color: uploaded ? AppColors.primaryGreen : Colors.orange,
      );
    }
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Find Offline SOS Nearby',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // ── Scan header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                Icon(
                  _isScanning
                      ? Icons.bluetooth_searching
                      : (_done ? Icons.bluetooth_disabled : Icons.bluetooth),
                  size: 48,
                  color: _isScanning ? AppColors.infoBlue : Colors.grey,
                ),
                const SizedBox(height: 12),
                Text(
                  _isScanning
                      ? 'Scanning for offline SOS broadcasts...'
                      : (_done
                            ? 'Scan complete. ${_victims.isEmpty ? 'No victims found.' : '${_victims.length} victim(s) found!'}'
                            : 'Tap the button to scan for nearby people in distress.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (_isScanning) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _stopScan,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.radar),
                    label: Text(_done ? 'Scan Again' : 'Start Scan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.criticalRed,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Victim list ──
          Expanded(
            child: _victims.isEmpty
                ? Center(
                    child: Text(
                      _isScanning
                          ? 'Listening...'
                          : (_done
                                ? 'No offline SOS broadcasts found nearby.'
                                : 'Press Start Scan to begin.'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _victims.length,
                    itemBuilder: (ctx, i) {
                      final victim = _victims.values.elementAt(i);
                      final alreadyResponded = _responded.contains(
                        victim.beacon.uuidHash,
                      );
                      return _VictimCard(
                        victim: victim,
                        alreadyResponded: alreadyResponded,
                        onRelay: () => _relayAndAck(victim),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Data class for a found victim during scan
// ----------------------------------------------------------------

class _FoundVictim {
  final BleBeacon beacon;
  final int rssi;
  final String distance;
  const _FoundVictim({
    required this.beacon,
    required this.rssi,
    required this.distance,
  });
}

// ----------------------------------------------------------------
// Victim Card Widget
// ----------------------------------------------------------------

class _VictimCard extends StatelessWidget {
  final _FoundVictim victim;
  final bool alreadyResponded;
  final VoidCallback onRelay;

  const _VictimCard({
    required this.victim,
    required this.alreadyResponded,
    required this.onRelay,
  });

  IconData _iconFor(String type) {
    switch (type.toLowerCase()) {
      case 'medical':
        return Icons.local_hospital;
      case 'fire':
        return Icons.local_fire_department;
      default:
        return Icons.emergency;
    }
  }

  @override
  Widget build(BuildContext context) {
    final beacon = victim.beacon;
    final hasLocation = beacon.lat != 0.0 || beacon.lng != 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.criticalRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _iconFor(beacon.incidentTypeString),
                color: AppColors.criticalRed,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${beacon.incidentTypeString} Emergency',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.bluetooth, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        victim.distance,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.signal_cellular_alt,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'RSSI: ${victim.rssi} dBm',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  if (hasLocation)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${beacon.lat.toStringAsFixed(4)}, ${beacon.lng.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  alreadyResponded
                      ? Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.primaryGreen,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Responded — SOS relayed',
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : FilledButton.icon(
                          onPressed: onRelay,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Acknowledge & Relay SOS'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.criticalRed,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
