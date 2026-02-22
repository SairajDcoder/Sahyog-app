import 'package:flutter/material.dart';
import '../../core/ble_scanner_service.dart';
import '../../core/ble_payload_codec.dart';
import 'mesh_alert_panel.dart';
import '../../theme/app_colors.dart';

class GlobalMeshOverlay extends StatefulWidget {
  final Widget child;

  const GlobalMeshOverlay({super.key, required this.child});

  @override
  State<GlobalMeshOverlay> createState() => _GlobalMeshOverlayState();
}

class _GlobalMeshOverlayState extends State<GlobalMeshOverlay> {
  BleBeacon? _detectedBeacon;
  String _detectedDistance = '';

  @override
  void initState() {
    super.initState();
    BleScannerService.instance.beaconDetectedNotifier.addListener(
      _onMeshBeaconDetected,
    );
    BleScannerService.instance.distanceNotifier.addListener(
      _onMeshDistanceUpdated,
    );
  }

  @override
  void dispose() {
    BleScannerService.instance.beaconDetectedNotifier.removeListener(
      _onMeshBeaconDetected,
    );
    BleScannerService.instance.distanceNotifier.removeListener(
      _onMeshDistanceUpdated,
    );
    super.dispose();
  }

  void _onMeshBeaconDetected() {
    final beacon = BleScannerService.instance.beaconDetectedNotifier.value;
    if (beacon != null && mounted) {
      setState(() {
        _detectedBeacon = beacon;
        _detectedDistance =
            BleScannerService.instance.distanceNotifier.value[beacon
                .uuidHash] ??
            'Nearby';
      });
    }
  }

  void _onMeshDistanceUpdated() {
    if (_detectedBeacon != null && mounted) {
      final distance = BleScannerService
          .instance
          .distanceNotifier
          .value[_detectedBeacon!.uuidHash];
      if (distance != null && distance != _detectedDistance) {
        setState(() {
          _detectedDistance = distance;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_detectedBeacon != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 80, // Sit above bottom nav bar approximately
            child: Material(
              type: MaterialType.transparency,
              child: MeshAlertPanel(
                beacon: _detectedBeacon!,
                distance: _detectedDistance,
                onRespond: () {
                  BleScannerService.instance.sendAckBeacon(
                    _detectedBeacon!.uuidHash,
                  );
                  setState(() {
                    _detectedBeacon = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Relay started! Acknowledgment sent via BLE.',
                      ),
                      backgroundColor: AppColors.primaryGreen,
                    ),
                  );
                },
                onDismiss: () {
                  setState(() {
                    _detectedBeacon = null;
                  });
                },
              ),
            ),
          ),
      ],
    );
  }
}
