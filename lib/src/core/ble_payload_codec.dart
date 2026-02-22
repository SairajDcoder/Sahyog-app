library;

import 'dart:typed_data';

/// BLE Payload Codec — encodes/decodes 18-byte SOS beacons.
///
/// Payload layout (18 bytes):
///   Byte 0:    Flag (0x50=SOS, 0xCA=Cancel, 0xAC=ACK)
///   Byte 1-4:  Latitude (float32 little-endian)
///   Byte 5-8:  Longitude (float32 little-endian)
///   Byte 9:    Incident type (0x01=Emergency, 0x02=Medical, 0x03=Fire)
///   Byte 10-13: Timestamp (uint32 Unix epoch seconds)
///   Byte 14-17: UUID hash (CRC32 of full UUID string)

// ─────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────

/// Sahyog manufacturer ID — "SH" in ASCII (0x5348)
const int kSahyogManufacturerId = 0x5348;

/// BLE beacon flag bytes
const int kFlagSos = 0x50; // 'P' for panic/SOS
const int kFlagCancel = 0xCA;
const int kFlagAck = 0xAC;

/// Incident type codes
const int kTypeEmergency = 0x01;
const int kTypeMedical = 0x02;
const int kTypeFire = 0x03;

// ─────────────────────────────────────────────────────────────
// Decoded Beacon
// ─────────────────────────────────────────────────────────────

class BleBeacon {
  const BleBeacon({
    required this.flag,
    required this.lat,
    required this.lng,
    required this.incidentType,
    required this.timestamp,
    required this.uuidHash,
  });

  final int flag;
  final double lat;
  final double lng;
  final int incidentType;
  final int timestamp; // Unix epoch seconds
  final int uuidHash; // CRC32

  bool get isSos => flag == kFlagSos;
  bool get isCancel => flag == kFlagCancel;
  bool get isAck => flag == kFlagAck;

  String get incidentTypeString {
    switch (incidentType) {
      case kTypeEmergency:
        return 'Emergency';
      case kTypeMedical:
        return 'Medical';
      case kTypeFire:
        return 'Fire';
      default:
        return 'Emergency';
    }
  }

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  @override
  String toString() =>
      'BleBeacon(flag=0x${flag.toRadixString(16)}, lat=$lat, lng=$lng, '
      'type=$incidentTypeString, ts=$timestamp, hash=0x${uuidHash.toRadixString(16)})';
}

// ─────────────────────────────────────────────────────────────
// Codec
// ─────────────────────────────────────────────────────────────

class BlePayloadCodec {
  BlePayloadCodec._();

  /// Encode an SOS beacon into 18 bytes of manufacturer data.
  static Uint8List encode({
    required int flag,
    required double lat,
    required double lng,
    int incidentType = kTypeEmergency,
    int? timestampOverride,
    required int uuidHash,
  }) {
    final buffer = ByteData(18);

    // Byte 0: Flag
    buffer.setUint8(0, flag);

    // Bytes 1-4: Latitude (float32 LE)
    buffer.setFloat32(1, lat, Endian.little);

    // Bytes 5-8: Longitude (float32 LE)
    buffer.setFloat32(5, lng, Endian.little);

    // Byte 9: Incident type
    buffer.setUint8(9, incidentType);

    // Bytes 10-13: Timestamp (uint32 LE)
    final ts =
        timestampOverride ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    buffer.setUint32(10, ts, Endian.little);

    // Bytes 14-17: UUID hash (uint32 LE)
    buffer.setUint32(14, uuidHash, Endian.little);

    return buffer.buffer.asUint8List();
  }

  /// Decode 18 bytes of manufacturer data into a BleBeacon.
  /// Returns null if data is too short or invalid.
  static BleBeacon? decode(Uint8List data) {
    if (data.length < 18) return null;

    final buffer = ByteData.sublistView(data);

    final flag = buffer.getUint8(0);

    // Validate flag
    if (flag != kFlagSos && flag != kFlagCancel && flag != kFlagAck) {
      return null;
    }

    final lat = buffer.getFloat32(1, Endian.little);
    final lng = buffer.getFloat32(5, Endian.little);

    // Basic lat/lng sanity check
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    final incidentType = buffer.getUint8(9);
    final timestamp = buffer.getUint32(10, Endian.little);
    final uuidHash = buffer.getUint32(14, Endian.little);

    // Timestamp freshness check (reject beacons older than 24 hours to prevent timezone/drift issues)
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((now - timestamp).abs() > 86400) return null;

    return BleBeacon(
      flag: flag,
      lat: lat,
      lng: lng,
      incidentType: incidentType,
      timestamp: timestamp,
      uuidHash: uuidHash,
    );
  }

  /// Encode an ACK beacon (minimal payload — only flag + uuid_hash matter).
  static Uint8List encodeAck(int uuidHash) {
    return encode(
      flag: kFlagAck,
      lat: 0,
      lng: 0,
      incidentType: 0,
      uuidHash: uuidHash,
    );
  }

  /// Encode a cancellation beacon.
  static Uint8List encodeCancel({
    required double lat,
    required double lng,
    required int uuidHash,
  }) {
    return encode(flag: kFlagCancel, lat: lat, lng: lng, uuidHash: uuidHash);
  }

  /// Incident type string → byte code.
  static int incidentTypeCode(String type) {
    switch (type.toLowerCase()) {
      case 'medical':
        return kTypeMedical;
      case 'fire':
        return kTypeFire;
      default:
        return kTypeEmergency;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// CRC32 — lightweight hash for UUID → 4-byte mapping
// ─────────────────────────────────────────────────────────────

class Crc32 {
  Crc32._();

  static final List<int> _table = _generateTable();

  static List<int> _generateTable() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if (crc & 1 == 1) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
      table[i] = crc;
    }
    return table;
  }

  /// Compute CRC32 hash of a string. Returns unsigned 32-bit integer.
  static int compute(String input) {
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < input.length; i++) {
      crc = _table[(crc ^ input.codeUnitAt(i)) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
