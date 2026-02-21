import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sahyog_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // Stores SOS incidents that haven't been synced to the server yet
    await db.execute('''
      CREATE TABLE local_incidents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reporter_id TEXT NOT NULL,
        location_lat REAL,
        location_lng REAL,
        media_paths TEXT,
        captured_at TEXT NOT NULL,
        status TEXT DEFAULT 'pending_sync'
      )
    ''');
  }

  Future<int> insertIncident(Map<String, dynamic> incident) async {
    final db = await instance.database;

    // Convert List<String> of media paths to JSON string before saving
    final dataToSave = Map<String, dynamic>.from(incident);
    if (dataToSave.containsKey('media_paths') &&
        dataToSave['media_paths'] is List) {
      dataToSave['media_paths'] = jsonEncode(dataToSave['media_paths']);
    }

    return await db.insert('local_incidents', dataToSave);
  }

  Future<List<Map<String, dynamic>>> getPendingIncidents() async {
    final db = await instance.database;
    final results = await db.query(
      'local_incidents',
      where: 'status = ?',
      whereArgs: ['pending_sync'],
    );

    // Convert JSON strings back to lists
    return results.map((row) {
      final map = Map<String, dynamic>.from(row);
      if (map['media_paths'] != null && map['media_paths'] is String) {
        try {
          map['media_paths'] = jsonDecode(map['media_paths']);
        } catch (_) {
          map['media_paths'] = [];
        }
      }
      return map;
    }).toList();
  }

  Future<int> markIncidentSynced(int id) async {
    final db = await instance.database;
    return db.update(
      'local_incidents',
      {'status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
