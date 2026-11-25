class DocumentModel {
  const DocumentModel({
    required this.id,
    required this.name,
    required this.originalFileName,
    required this.localFilePath,
    this.folderId,
    required this.isFavorite,
    required this.openCount,
    this.lastOpenedAt,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String originalFileName;
  final String localFilePath;
  final int? folderId;
  final bool isFavorite;
  final int openCount;
  final DateTime? lastOpenedAt;
  final DateTime createdAt;

  factory DocumentModel.fromMap(Map<String, dynamic> map) {
    return DocumentModel(
      id: map['id'] as int,
      name: map['name'] as String,
      originalFileName: map['original_file_name'] as String,
      localFilePath: map['local_file_path'] as String,
      folderId: map['folder_id'] as int?,
      isFavorite: (map['is_favorite'] as int) == 1,
      openCount: map['open_count'] as int? ?? 0,
      lastOpenedAt: map['last_opened_at'] == null
          ? null
          : DateTime.parse(map['last_opened_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
