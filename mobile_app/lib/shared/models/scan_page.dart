import 'document_paper_size.dart';

class ScanPage {
  const ScanPage({
    required this.id,
    required this.imagePath,
    required this.createdAt,
    this.paperSize = DocumentPaperSize.auto,
  });

  final String id;
  final String imagePath;
  final DateTime createdAt;
  final DocumentPaperSize paperSize;

  ScanPage copyWith({
    String? id,
    String? imagePath,
    DateTime? createdAt,
    DocumentPaperSize? paperSize,
  }) {
    return ScanPage(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      paperSize: paperSize ?? this.paperSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
      'paperSize': paperSize.name,
    };
  }

  factory ScanPage.fromJson(Map<String, dynamic> json) {
    return ScanPage(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      paperSize: DocumentPaperSizeLabels.fromName(json['paperSize'] as String?),
    );
  }
}
