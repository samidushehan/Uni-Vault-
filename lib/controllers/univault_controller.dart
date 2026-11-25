import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';

class UnivaultController extends ChangeNotifier {
  UnivaultController();

  final DatabaseService _database = DatabaseService.instance;
  final StorageService _storage = StorageService.instance;

  Future<void> initialize() async {
    await _database.database;
    notifyListeners();
  }

  Future<List<FolderModel>> loadFolders({int? parentId}) async =>
      _database.getFolders(parentId: parentId);

  Future<List<FolderModel>> loadAllFolders() async => _database.getAllFolders();

  Future<List<FolderModel>> loadFolderPath(int folderId) async =>
      _database.getFolderPath(folderId);

  Future<Set<int>> loadDescendantFolderIds(int folderId) async =>
      _database.getDescendantFolderIds(folderId);

  Future<(int documentCount, int subfolderCount)> loadFolderCounts(
    int folderId,
  ) async => _database.getFolderCounts(folderId);

  Future<List<DocumentModel>> loadRootDocuments() async =>
      _database.getDocuments(folderId: null);

  Future<List<DocumentModel>> loadAllDocuments() async =>
      _database.getAllDocuments();

  Future<List<DocumentModel>> loadDocumentsForFolder(int folderId) async =>
      _database.getDocuments(folderId: folderId);

  Future<List<DocumentModel>> loadFavoriteDocuments() async =>
      _database.getFavoriteDocuments();

  Future<List<DocumentModel>> loadRecentlyOpenedDocuments() async =>
      _database.getRecentlyOpenedDocuments();

  Future<int> countFolders() async => (await loadAllFolders()).length;

  Future<int> countDocuments() async => _database.getTotalDocumentCount();

  Future<void> createFolder(String name, {int? parentId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Folder name cannot be empty.');
    }

    final exists = await _database.folderNameExists(
      trimmed,
      parentId: parentId,
    );
    if (exists) {
      throw const FormatException('A folder with that name already exists.');
    }

    await _database.createFolder(trimmed, parentId: parentId);
    notifyListeners();
  }

  Future<void> renameFolder(int folderId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Folder name cannot be empty.');
    }

    final folders = await _database.getAllFolders();
    FolderModel? folder;
    for (final item in folders) {
      if (item.id == folderId) {
        folder = item;
        break;
      }
    }
    if (folder == null) {
      throw const FormatException('This folder no longer exists.');
    }

    final exists = await _database.folderNameExists(
      trimmed,
      parentId: folder.parentId,
      excludeId: folderId,
    );
    if (exists) {
      throw const FormatException('A folder with that name already exists.');
    }

    await _database.renameFolder(folderId, trimmed);
    notifyListeners();
  }

  Future<void> moveFolder(int folderId, int? parentId) async {
    await _database.moveFolder(folderId, parentId);
    notifyListeners();
  }

  Future<void> deleteFolder(int folderId) async {
    await _database.deleteFolder(folderId);
    notifyListeners();
  }

  Future<void> renameDocument(int documentId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Document name cannot be empty.');
    }

    await _database.renameDocument(documentId, trimmed);
    notifyListeners();
  }

  Future<void> moveDocument(int documentId, int? folderId) async {
    await _database.moveDocument(documentId, folderId);
    notifyListeners();
  }

  Future<void> toggleFavorite(DocumentModel document) async {
    await _database.toggleFavorite(document.id, !document.isFavorite);
    notifyListeners();
  }

  Future<void> deleteDocument(DocumentModel document) async {
    await _database.deleteDocument(document.id);
    await _storage.deleteDocumentFile(document.localFilePath);
    notifyListeners();
  }

  Future<void> openDocument(DocumentModel document) async {
    await _database.recordOpen(document.id);
    notifyListeners();
  }

  Future<void> importPdfFiles(List<String> filePaths, {int? folderId}) async {
    if (filePaths.isEmpty) {
      return;
    }

    final copiedPaths = <String>[];

    for (final path in filePaths) {
      final lower = path.toLowerCase();
      if (!lower.endsWith('.pdf')) {
        throw const FormatException('Only PDF files can be imported.');
      }

      final originalFileName = p.basename(path);
      final alreadyExists = await _database.documentExistsByOriginalName(
        originalFileName,
      );
      if (alreadyExists) {
        continue;
      }

      try {
        final savedPath = await _storage.saveImportedPdf(
          sourcePath: path,
          originalFileName: originalFileName,
        );

        final displayName = p.basenameWithoutExtension(originalFileName);
        await _database.addDocument(
          name: displayName,
          originalFileName: originalFileName,
          localFilePath: savedPath,
          folderId: folderId,
        );
        copiedPaths.add(savedPath);
      } on FileSystemException {
        continue;
      }
    }

    if (copiedPaths.isEmpty) {
      throw const FormatException('No new PDFs were imported.');
    }

    notifyListeners();
  }
}
