import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/download_task.dart';

class DatabaseService {
  static Database? _database;
  static const String _tableName = 'download_tasks';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'stream_grabber.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        websiteUrl TEXT NOT NULL,
        outputPath TEXT NOT NULL,
        fileName TEXT NOT NULL,
        status INTEGER NOT NULL,
        progress REAL NOT NULL,
        totalSegments INTEGER NOT NULL,
        downloadedSegments INTEGER NOT NULL,
        errorMessage TEXT,
        createdAt TEXT NOT NULL,
        completedAt TEXT
      )
    ''');
  }

  Future<void> insertTask(DownloadTask task) async {
    final db = await database;
    await db.insert(
      _tableName,
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTask(DownloadTask task) async {
    final db = await database;
    await db.update(
      _tableName,
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<DownloadTask?> getTask(String id) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return DownloadTask.fromMap(maps.first);
  }

  Future<List<DownloadTask>> getAllTasks() async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      orderBy: 'createdAt DESC',
    );

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<List<DownloadTask>> getTasksByStatus(DownloadStatus status) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: [status.index],
      orderBy: 'createdAt DESC',
    );

    return maps.map((map) => DownloadTask.fromMap(map)).toList();
  }

  Future<void> clearCompletedTasks() async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'status = ?',
      whereArgs: [DownloadStatus.completed.index],
    );
  }

  Future<void> clearAllTasks() async {
    final db = await database;
    await db.delete(_tableName);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
