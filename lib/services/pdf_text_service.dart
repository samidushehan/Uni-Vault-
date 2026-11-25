import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

import '../models/pdf_text_chunk.dart';

class PdfTextException implements Exception {
  const PdfTextException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PdfTextService {
  static const int _maxChunkLength = 1800;
  static const int _defaultMaxRelevantCharacters = 18000;
  static const int _defaultMaxRelevantChunks = 10;
  static Future<void>? _initialization;

  Future<List<PdfTextChunk>> extractChunks(String filePath) async {
    final chunks = await _readChunks(filePath).toList();
    if (chunks.isEmpty) {
      throw _noExtractableText;
    }
    return chunks;
  }

  Future<List<PdfTextChunk>> extractRelevantChunks(
    String filePath,
    String query, {
    int maxCharacters = _defaultMaxRelevantCharacters,
    int maxChunks = _defaultMaxRelevantChunks,
  }) async {
    if (maxCharacters <= 0 || maxChunks <= 0) {
      throw ArgumentError('Relevant text limits must be positive.');
    }

    final terms = _searchTerms(query);
    final matches = <({int index, PdfTextChunk chunk, int score})>[];
    final fallback = <({int index, PdfTextChunk chunk, int score})>[];
    var fallbackCharacters = 0;
    var chunkIndex = 0;

    await for (final chunk in _readChunks(filePath)) {
      if (fallback.length < maxChunks &&
          fallbackCharacters + chunk.text.length <= maxCharacters) {
        fallback.add((index: chunkIndex, chunk: chunk, score: 0));
        fallbackCharacters += chunk.text.length;
      }

      final score = _score(chunk.text, terms);
      if (score > 0) {
        _retainBestChunks(
          matches,
          (index: chunkIndex, chunk: chunk, score: score),
          maxCharacters: maxCharacters,
          maxChunks: maxChunks,
        );
      }
      chunkIndex++;
    }

    if (chunkIndex == 0) {
      throw _noExtractableText;
    }
    final selected = matches.isEmpty ? fallback : matches;
    if (selected.isEmpty) {
      throw const PdfTextException(
        'Could not select readable text from this PDF.',
      );
    }
    selected.sort((left, right) => left.index.compareTo(right.index));
    return selected.map((entry) => entry.chunk).toList(growable: false);
  }

  Stream<PdfTextChunk> _readChunks(String filePath) async* {
    if (!filePath.toLowerCase().endsWith('.pdf')) {
      throw const PdfTextException('Only PDF files can be processed.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw const PdfTextException(
        'This PDF is no longer available in local storage.',
      );
    }
    if (await file.length() == 0) {
      throw const PdfTextException('This PDF is empty or damaged.');
    }

    try {
      _initialization ??= pdfrxFlutterInitialize();
      await _initialization;
      final document = await PdfDocument.openFile(filePath);
      try {
        for (final page in document.pages) {
          final rawText = await page.loadText();
          final text = rawText?.fullText.trim() ?? '';
          if (text.isEmpty) {
            continue;
          }
          for (final chunk in _splitPageText(page.pageNumber, text)) {
            yield chunk;
          }
        }
      } finally {
        await document.dispose();
      }
    } on PdfTextException {
      rethrow;
    } on Exception {
      throw const PdfTextException(
        'Could not read text from this PDF. It may be damaged, encrypted, or image-only.',
      );
    }
  }

  static const PdfTextException _noExtractableText = PdfTextException(
    'No selectable text was found. This may be a scanned or image-only PDF; OCR is required before AI features can use it.',
  );

  void _retainBestChunks(
    List<({int index, PdfTextChunk chunk, int score})> selected,
    ({int index, PdfTextChunk chunk, int score}) candidate, {
    required int maxCharacters,
    required int maxChunks,
  }) {
    final ranked = [...selected, candidate]
      ..sort((left, right) {
        final scoreDifference = right.score - left.score;
        return scoreDifference != 0
            ? scoreDifference
            : left.index.compareTo(right.index);
      });

    final bounded = <({int index, PdfTextChunk chunk, int score})>[];
    var characterCount = 0;
    for (final entry in ranked) {
      if (bounded.length >= maxChunks) {
        break;
      }
      if (characterCount + entry.chunk.text.length > maxCharacters) {
        continue;
      }
      bounded.add(entry);
      characterCount += entry.chunk.text.length;
    }
    selected
      ..clear()
      ..addAll(bounded);
  }

  Iterable<PdfTextChunk> _splitPageText(int pageNumber, String text) sync* {
    var start = 0;

    while (start < text.length) {
      var end = (start + _maxChunkLength).clamp(0, text.length).toInt();
      if (end < text.length) {
        final paragraphBreak = text.lastIndexOf('\n', end);
        final spaceBreak = text.lastIndexOf(' ', end);
        final breakAt = paragraphBreak > start + _maxChunkLength ~/ 2
            ? paragraphBreak
            : spaceBreak;
        if (breakAt > start + _maxChunkLength ~/ 2) {
          end = breakAt;
        }
      }

      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) {
        yield PdfTextChunk(pageNumber: pageNumber, text: chunk);
      }
      start = end;
      while (start < text.length && text[start].trim().isEmpty) {
        start++;
      }
    }
  }

  List<PdfTextChunk> selectRelevantChunks(
    List<PdfTextChunk> chunks,
    String query, {
    int maxCharacters = 18000,
    int maxChunks = 10,
  }) {
    if (chunks.isEmpty || maxChunks <= 0 || maxCharacters <= 0) {
      return const [];
    }

    final terms = _searchTerms(query);
    final ranked = chunks.indexed.toList()
      ..sort((left, right) {
        final scoreDifference =
            _score(right.$2.text, terms) - _score(left.$2.text, terms);
        return scoreDifference != 0 ? scoreDifference : left.$1 - right.$1;
      });

    final selected = <({int index, PdfTextChunk chunk})>[];
    var characterCount = 0;
    for (final (index, chunk) in ranked) {
      if (selected.length >= maxChunks) {
        break;
      }
      if (characterCount + chunk.text.length > maxCharacters) {
        continue;
      }
      selected.add((index: index, chunk: chunk));
      characterCount += chunk.text.length;
    }

    if (selected.isEmpty && chunks.isNotEmpty) {
      selected.add((index: 0, chunk: chunks.first));
    }
    selected.sort((left, right) => left.index.compareTo(right.index));
    return selected.map((entry) => entry.chunk).toList();
  }

  List<PdfTextChunk> selectOverviewChunks(
    List<PdfTextChunk> chunks, {
    int maxCharacters = 24000,
  }) {
    if (chunks.isEmpty) {
      return const [];
    }

    final totalCharacters = chunks.fold<int>(
      0,
      (total, chunk) => total + chunk.text.length,
    );
    if (totalCharacters <= maxCharacters) {
      return chunks;
    }

    final selected = <PdfTextChunk>[];
    var characterCount = 0;
    final sampleCount = (maxCharacters ~/ _maxChunkLength)
        .clamp(1, chunks.length)
        .toInt();
    for (var index = 0; index < sampleCount; index++) {
      final chunkIndex = sampleCount == 1
          ? 0
          : (index * (chunks.length - 1) / (sampleCount - 1)).round();
      final chunk = chunks[chunkIndex];
      if (characterCount + chunk.text.length > maxCharacters) {
        continue;
      }
      selected.add(chunk);
      characterCount += chunk.text.length;
    }
    return selected;
  }

  Set<String> _searchTerms(String query) {
    const ignored = {
      'about',
      'after',
      'also',
      'are',
      'can',
      'could',
      'does',
      'from',
      'have',
      'into',
      'that',
      'the',
      'their',
      'them',
      'this',
      'what',
      'when',
      'where',
      'which',
      'with',
      'would',
    };
    return RegExp(r'[a-z0-9]{3,}')
        .allMatches(query.toLowerCase())
        .map((match) => match.group(0)!)
        .where((term) => !ignored.contains(term))
        .toSet();
  }

  int _score(String text, Set<String> terms) {
    if (terms.isEmpty) {
      return 0;
    }
    final normalized = text.toLowerCase();
    return terms.where(normalized.contains).length;
  }
}
