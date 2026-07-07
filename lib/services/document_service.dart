import 'dart:io';
import '../core/logger.dart';

class DocumentService {
  final Logger _log = Logger('DocumentService');

  static const _supportedExtensions = {'.txt', '.md', '.csv', '.log', '.json', '.yaml', '.yml', '.xml', '.html', '.htm'};
  static const int _maxFileSize = 10 * 1024 * 1024;
  static const int _maxChunkSize = 2000;

  bool isSupported(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _supportedExtensions.contains('.$ext');
  }

  Future<DocumentResult?> read(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return DocumentResult(error: 'File not found: $path');
      }

      final stats = await file.stat();
      if (stats.size > _maxFileSize) {
        return DocumentResult(error: 'File too large (${stats.size ~/ 1024} KB). Max is 10 MB.');
      }

      final content = await file.readAsString();
      if (content.isEmpty) {
        return DocumentResult(error: 'File is empty.');
      }

      final name = path.split(RegExp(r'[/\\]')).last;
      final chunks = _chunkContent(content);

      _log.i('Read "$name": ${content.length} chars in ${chunks.length} chunks');
      return DocumentResult(
        fileName: name,
        fullText: content,
        chunks: chunks,
      );
    } catch (e) {
      _log.e('Failed to read $path: $e');
      return DocumentResult(error: 'Failed to read file: $e');
    }
  }

  List<String> _chunkContent(String text) {
    if (text.length <= _maxChunkSize) return [text];

    final chunks = <String>[];
    final lines = text.split('\n');
    final buffer = StringBuffer();
    for (final line in lines) {
      if (buffer.length + line.length + 1 > _maxChunkSize && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.writeln(line);
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks;
  }

  String formatForMemory(String fileName, List<String> chunks) {
    if (chunks.length == 1) {
      return 'Document "$fileName":\n${chunks.first}';
    }
    final lines = <String>['Document "$fileName" (${chunks.length} sections):'];
    for (int i = 0; i < chunks.length; i++) {
      lines.add('\n--- Section ${i + 1} ---\n${chunks[i]}');
    }
    return lines.join();
  }
}

class DocumentResult {
  final String? fileName;
  final String? fullText;
  final List<String>? chunks;
  final String? error;

  DocumentResult({this.fileName, this.fullText, this.chunks, this.error});

  bool get isSuccess => error == null;
}
