class BackupArchive {
  const BackupArchive({
    required this.name,
    required this.size,
    required this.createdAt,
  });

  final String name;
  final int size;
  final DateTime createdAt;

  factory BackupArchive.fromJson(Map<String, dynamic> json) {
    return BackupArchive(
      name: json['name']?.toString() ?? '',
      size: json['size'] is int
          ? json['size'] as int
          : int.tryParse(json['size']?.toString() ?? '') ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
