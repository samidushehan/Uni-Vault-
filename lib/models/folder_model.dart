class FolderModel {
  const FolderModel({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  final int id;
  final String name;
  final int? parentId;
  final DateTime createdAt;

  factory FolderModel.fromMap(Map<String, dynamic> map) {
    return FolderModel(
      id: map['id'] as int,
      name: map['name'] as String,
      parentId: map['parent_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
