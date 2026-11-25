import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  Future<Directory> _pdfDirectory() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final pdfDirectory = Directory(p.join(appDirectory.path, 'pdf_library'));
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }
    return pdfDirectory;
  }

  Future<String> saveImportedPdf({
    required String sourcePath,
    required String originalFileName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const FileSystemException('The selected PDF could not be found.');
    }

    final directory = await _pdfDirectory();
    final safeFileName = _makeUniqueFileName(originalFileName, directory);
    final destination = File(p.join(directory.path, safeFileName));

    final bytes = await sourceFile.readAsBytes();
    final digest = sha256.convert(bytes).toString();

    if (await destination.exists()) {
      final existingDigest = sha256
          .convert(await destination.readAsBytes())
          .toString();
      if (existingDigest == digest) {
        throw const FileSystemException('This PDF has already been imported.');
      }
    }

    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  String _makeUniqueFileName(String originalFileName, Directory directory) {
    final cleanName = originalFileName.trim();
    if (cleanName.isEmpty) {
      return 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
    }

    final fileName = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final extension = p.extension(fileName).toLowerCase();
    final baseName = extension.isNotEmpty
        ? fileName.substring(0, fileName.length - extension.length)
        : fileName;

    final safeBase = baseName.isEmpty ? 'document' : baseName;
    final safeExtension = extension.isEmpty ? '.pdf' : extension;
    final candidate = '$safeBase$safeExtension';

    final target = File(p.join(directory.path, candidate));
    if (!target.existsSync()) {
      return candidate;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${safeBase}_$timestamp$safeExtension';
  }

  Future<void> deleteDocumentFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
