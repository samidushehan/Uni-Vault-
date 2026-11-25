import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document_model.dart';
import '../models/folder_model.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final documentDirectory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(documentDirectory.path, 'univault.db');

    _database = await openDatabase(
      dbPath,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            parent_id INTEGER,
            FOREIGN KEY (parent_id) REFERENCES folders(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX index_folders_sibling_name
          ON folders(COALESCE(parent_id, 0), name COLLATE NOCASE)
        ''');

        await db.execute('''
          CREATE TABLE documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            original_file_name TEXT NOT NULL,
            local_file_path TEXT NOT NULL,
            folder_id INTEGER,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            open_count INTEGER NOT NULL DEFAULT 0,
            last_opened_at TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE folders ADD COLUMN parent_id INTEGER '
            'REFERENCES folders(id) ON DELETE SET NULL',
          );
          await db.execute('''
            CREATE UNIQUE INDEX index_folders_sibling_name
            ON folders(COALESCE(parent_id, 0), name COLLATE NOCASE)
          ''');
        }
      },
    );

    return _database!;
  }

  Future<List<FolderModel>> getFolders({int? parentId}) async {
    final db = await database;
    final maps = await db.query(
      'folders',
      where: parentId == null ? 'parent_id IS NULL' : 'parent_id = ?',
      whereArgs: parentId == null ? null : [parentId],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return maps.map(FolderModel.fromMap).toList();
  }

  Future<List<FolderModel>> getAllFolders() async {
    final db = await database;
    final maps = await db.query('folders', orderBy: 'name COLLATE NOCASE ASC');
    return maps.map(FolderModel.fromMap).toList();
  }

  Future<List<FolderModel>> getFolderPath(int folderId) async {
    final folders = await getAllFolders();
    final byId = {for (final folder in folders) folder.id: folder};
    final path = <FolderModel>[];
    final visited = <int>{};
    var current = byId[folderId];
    while (current != null && visited.add(current.id)) {
      path.add(current);
      current = current.parentId == null ? null : byId[current.parentId];
    }
    return path.reversed.toList();
  }

  Future<Set<int>> getDescendantFolderIds(int folderId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      WITH RECURSIVE descendants(id) AS (
        SELECT id FROM folders WHERE parent_id = ?
        UNION ALL
        SELECT folders.id
        FROM folders
        INNER JOIN descendants ON folders.parent_id = descendants.id
      )
      SELECT id FROM descendants
      ''',
      [folderId],
    );
    return rows.map((row) => row['id'] as int).toSet();
  }

  Future<int> createFolder(String name, {int? parentId}) async {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) {
      throw const FormatException('Folder name cannot be empty.');
    }

    final db = await database;
    try {
      return await db.insert('folders', {
        'name': cleanedName,
        'parent_id': parentId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const FormatException(
          'A folder with that name already exists here.',
        );
      }
      rethrow;
    }
  }

  Future<void> renameFolder(int folderId, String newName) async {
    final cleanedName = newName.trim();
    if (cleanedName.isEmpty) {
      throw const FormatException('Folder name cannot be empty.');
    }

    final db = await database;
    try {
      await db.update(
        'folders',
        {'name': cleanedName},
        where: 'id = ?',
        whereArgs: [folderId],
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const FormatException(
          'A folder with that name already exists here.',
        );
      }
      rethrow;
    }
  }

  Future<void> deleteFolder(int folderId) async {
    final db = await database;
    await db.transaction((transaction) async {
      final exists = await transaction.query(
        'folders',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [folderId],
        limit: 1,
      );
      if (exists.isEmpty) {
        return;
      }
      await transaction.rawUpdate(
        '''
        UPDATE documents
        SET folder_id = NULL
        WHERE folder_id IN (
          WITH RECURSIVE descendants(id) AS (
            SELECT id FROM folders WHERE id = ?
            UNION ALL
            SELECT folders.id
            FROM folders
            INNER JOIN descendants ON folders.parent_id = descendants.id
          )
          SELECT id FROM descendants
        )
        ''',
        [folderId],
      );
      await transaction.rawDelete(
        '''
        DELETE FROM folders
        WHERE id IN (
          WITH RECURSIVE descendants(id) AS (
            SELECT id FROM folders WHERE id = ?
            UNION ALL
            SELECT folders.id
            FROM folders
            INNER JOIN descendants ON folders.parent_id = descendants.id
          )
          SELECT id FROM descendants
        )
        ''',
        [folderId],
      );
    });
  }

  Future<void> moveFolder(int folderId, int? parentId) async {
    final db = await database;
    if (folderId == parentId) {
      throw const FormatException('A folder cannot be moved inside itself.');
    }
    if (parentId != null) {
      final descendants = await getDescendantFolderIds(folderId);
      if (descendants.contains(parentId)) {
        throw const FormatException(
          'A folder cannot be moved inside one of its own subfolders.',
        );
      }
    }
    try {
      final updated = await db.update(
        'folders',
        {'parent_id': parentId},
        where: 'id = ?',
        whereArgs: [folderId],
      );
      if (updated == 0) {
        throw const FormatException('This folder no longer exists.');
      }
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const FormatException(
          'A folder with that name already exists in the destination.',
        );
      }
      rethrow;
    }
  }

  Future<bool> folderNameExists(
    String name, {
    int? parentId,
    int? excludeId,
  }) async {
    final db = await database;
    final result = await db.query(
      'folders',
      columns: ['id'],
      where:
          'LOWER(name) = LOWER(?) AND id != ? AND '
          '${parentId == null ? 'parent_id IS NULL' : 'parent_id = ?'}',
      whereArgs: [name.trim(), excludeId ?? -1, ?parentId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<(int documentCount, int subfolderCount)> getFolderCounts(
    int folderId,
  ) async {
    final db = await database;
    final documents = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM documents WHERE folder_id = ?',
      [folderId],
    );
    final folders = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM folders WHERE parent_id = ?',
      [folderId],
    );
    return (
      documents.first['count'] as int? ?? 0,
      folders.first['count'] as int? ?? 0,
    );
  }

  Future<List<DocumentModel>> getDocuments({int? folderId}) async {
    final db = await database;

    final whereClause = folderId == null
        ? 'folder_id IS NULL'
        : 'folder_id = ?';
    final whereArgs = folderId == null ? <Object>[] : [folderId];

    final maps = await db.query(
      'documents',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    return maps.map(DocumentModel.fromMap).toList();
  }

  Future<List<DocumentModel>> getAllDocuments() async {
    final db = await database;
    final maps = await db.query('documents', orderBy: 'created_at DESC');
    return maps.map(DocumentModel.fromMap).toList();
  }

  Future<List<DocumentModel>> getFavoriteDocuments() async {
    final db = await database;
    final maps = await db.query(
      'documents',
      where: 'is_favorite = 1',
      orderBy: 'created_at DESC',
    );
    return maps.map(DocumentModel.fromMap).toList();
  }

  Future<List<DocumentModel>> getRecentlyOpenedDocuments() async {
    final db = await database;
    final maps = await db.query(
      'documents',
      where: 'last_opened_at IS NOT NULL',
      orderBy: 'last_opened_at DESC',
    );
    return maps.map(DocumentModel.fromMap).toList();
  }

  Future<int> addDocument({
    required String name,
    required String originalFileName,
    required String localFilePath,
    int? folderId,
  }) async {
    final db = await database;
    return db.insert('documents', {
      'name': name,
      'original_file_name': originalFileName,
      'local_file_path': localFilePath,
      'folder_id': folderId,
      'is_favorite': 0,
      'open_count': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> renameDocument(int documentId, String newName) async {
    final cleanedName = newName.trim();
    if (cleanedName.isEmpty) {
      throw const FormatException('Document name cannot be empty.');
    }

    final db = await database;
    await db.update(
      'documents',
      {'name': cleanedName},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  Future<void> moveDocument(int documentId, int? folderId) async {
    final db = await database;
    await db.update(
      'documents',
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  Future<void> toggleFavorite(int documentId, bool favorite) async {
    final db = await database;
    await db.update(
      'documents',
      {'is_favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  Future<void> deleteDocument(int documentId) async {
    final db = await database;
    await db.delete('documents', where: 'id = ?', whereArgs: [documentId]);
  }

  Future<void> recordOpen(int documentId) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE documents
      SET open_count = open_count + 1,
          last_opened_at = ?
      WHERE id = ?
      ''',
      [DateTime.now().toUtc().toIso8601String(), documentId],
    );
  }

  Future<bool> documentExistsByOriginalName(String originalFileName) async {
    final db = await database;
    final result = await db.query(
      'documents',
      columns: ['id'],
      where: 'LOWER(original_file_name) = LOWER(?)',
      whereArgs: [originalFileName],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<int> getFolderDocumentCount(int folderId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM documents WHERE folder_id = ?',
      [folderId],
    );
    final count = result.first['count'] as int? ?? 0;
    return count;
  }

  Future<int> getTotalDocumentCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM documents');
    return result.first['count'] as int? ?? 0;
  }
}
