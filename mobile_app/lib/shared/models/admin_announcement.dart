class AdminAnnouncement {
  const AdminAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    required this.tone,
    required this.isPinned,
    required this.isActive,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String message;
  final String tone;
  final bool isPinned;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AdminAnnouncement.fromJson(Map<String, dynamic> json) {
    return AdminAnnouncement(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      tone: json['tone'] as String? ?? 'info',
      isPinned: json['isPinned'] == true,
      isActive: json['isActive'] != false,
      startsAt: json['startsAt'] is String
          ? DateTime.tryParse(json['startsAt'] as String)
          : null,
      endsAt: json['endsAt'] is String
          ? DateTime.tryParse(json['endsAt'] as String)
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
