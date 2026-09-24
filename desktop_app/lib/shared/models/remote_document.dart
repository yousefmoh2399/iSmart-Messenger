import '../../core/network/media_url_resolver.dart';

class RemoteDocument {
  const RemoteDocument({
    required this.id,
    required this.fileName,
    required this.originalName,
    required this.mimeType,
    required this.pageCount,
    required this.fileSize,
    required this.downloadUrl,
    required this.ownerId,
    required this.ownerUsername,
    required this.ownerFullName,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
  });

  final String id;
  final String fileName;
  final String originalName;
  final String mimeType;
  final int pageCount;
  final int fileSize;
  final String downloadUrl;
  final String? ownerId;
  final String? ownerUsername;
  final String? ownerFullName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? folderId;

  factory RemoteDocument.fromJson(Map<String, dynamic> json) {
    return RemoteDocument(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      originalName: json['originalName'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/pdf',
      pageCount: json['pageCount'] as int? ?? 1,
      fileSize: json['fileSize'] as int? ?? 0,
      downloadUrl: resolveApiUrl(json['downloadUrl'] as String? ?? ''),
      ownerId: json['ownerId'] as String?,
      ownerUsername: json['ownerUsername'] as String?,
      ownerFullName: json['ownerFullName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      folderId: json['folderId'] as String?,
    );
  }

  RemoteDocument copyWith({
    String? id,
    String? fileName,
    String? originalName,
    String? mimeType,
    int? pageCount,
    int? fileSize,
    String? downloadUrl,
    String? ownerId,
    String? ownerUsername,
    String? ownerFullName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? folderId,
  }) {
    return RemoteDocument(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      originalName: originalName ?? this.originalName,
      mimeType: mimeType ?? this.mimeType,
      pageCount: pageCount ?? this.pageCount,
      fileSize: fileSize ?? this.fileSize,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      ownerId: ownerId ?? this.ownerId,
      ownerUsername: ownerUsername ?? this.ownerUsername,
      ownerFullName: ownerFullName ?? this.ownerFullName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      folderId: folderId, // intentional, allow clearing
    );
  }
}
