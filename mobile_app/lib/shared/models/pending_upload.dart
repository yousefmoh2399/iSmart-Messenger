class PendingUpload {
  const PendingUpload({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.pageCount,
    required this.fileSize,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String filePath;
  final int pageCount;
  final int fileSize;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'filePath': filePath,
      'pageCount': pageCount,
      'fileSize': fileSize,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    return PendingUpload(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      pageCount: json['pageCount'] as int,
      fileSize: json['fileSize'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
