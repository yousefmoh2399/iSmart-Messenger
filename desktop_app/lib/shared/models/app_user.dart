class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.departmentId,
    required this.branchId,
    required this.branchCode,
    required this.isOnline,
    required this.presenceStatus,
    required this.isActive,
    required this.avatarUrl,
    required this.lastSeen,
    required this.lastActiveAt,
    required this.permissions,
    required this.chatPreferences,
  });

  final String id;
  final String username;
  final String fullName;
  final String role;
  final String? departmentId;
  final String? branchId;
  final String branchCode;
  final bool isOnline;
  final String presenceStatus;
  final bool isActive;
  final String? avatarUrl;
  final DateTime? lastSeen;
  final DateTime? lastActiveAt;
  final Map<String, bool> permissions;
  final ChatPreferences chatPreferences;

  bool can(String permission) => permissions[permission] ?? false;
  bool get isAdmin => role == 'admin';
  bool get canManageChat =>
      isAdmin ||
      can('canCreateUsers') ||
      can('canCreateDepartments') ||
      can('canCreateRooms') ||
      can('canSendBroadcast') ||
      can('canModerateDepartment') ||
      can('canViewDepartmentLogs') ||
      can('canManageAnnouncements') ||
      can('canManageFiles') ||
      can('canManageBranches') ||
      can('canManageRoles') ||
      can('canManageSystem') ||
      can('canManageUpdates') ||
      can('canManageBackups') ||
      can('canManageTickets') ||
      canViewPrinterModule;

  bool get canViewSnipeit => isAdmin || can('canViewSnipeit');

  bool get canViewPrinterModule =>
      isAdmin ||
      can('canViewPrinters') ||
      can('canManagePrinters') ||
      can('canSyncPrinters') ||
      can('canExportPrinterReports');

  bool get canManagePrinterModule => isAdmin || can('canManagePrinters');
  bool get canSyncPrinterModule =>
      isAdmin || can('canSyncPrinters') || can('canManagePrinters');
  bool get canExportPrinterReports =>
      isAdmin || can('canExportPrinterReports') || can('canManagePrinters');

  bool get canViewItAssets =>
      isAdmin ||
      can('canViewItAssets') ||
      can('canManageItAssets') ||
      can('canExecuteItAssets') ||
      can('canAuditItAssets') ||
      can('canManageItInventory') ||
      can('canInspectDamagedItAssets') ||
      can('canManageItProcurement') ||
      can('canExportItReports') ||
      can('canManageItSettings') ||
      can('canCloseItPeriods') ||
      can('canScanItAssets') ||
      can('canScanItSpareParts') ||
      can('canScanItInventory') ||
      can('canDeleteItAssets');
  bool get canManageItAssets => isAdmin || can('canManageItAssets');
  bool get canExecuteItAssets =>
      isAdmin || can('canExecuteItAssets') || can('canManageItAssets');
  bool get canAuditItAssets => isAdmin || can('canAuditItAssets');
  bool get canManageItInventory =>
      isAdmin || canManageItAssets || can('canManageItInventory');
  bool get canInspectDamagedItAssets =>
      isAdmin || canManageItAssets || can('canInspectDamagedItAssets');
  bool get canManageItProcurement =>
      isAdmin || canManageItAssets || can('canManageItProcurement');
  bool get canExportItReports =>
      isAdmin || can('canExportItReports') || canAuditItAssets;
  bool get canManageItSettings =>
      isAdmin || canManageItAssets || can('canManageItSettings');
  bool get canCloseItPeriods => isAdmin || can('canCloseItPeriods');
  bool get canScanItAssets =>
      isAdmin || canManageItAssets || can('canScanItAssets');
  bool get canScanItSpareParts =>
      isAdmin || canManageItAssets || can('canScanItSpareParts');
  bool get canScanItInventory =>
      isAdmin || canManageItInventory || can('canScanItInventory');
  bool get canDeleteItAssets => isAdmin || can('canDeleteItAssets');

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final permissionsJson =
        json['permissions'] as Map<String, dynamic>? ?? const {};
    final chatPrefsJson = json['chatPreferences'] as Map<String, dynamic>?;
    return AppUser(
      id: json['id'] as String,
      username: json['username'] as String,
      fullName: json['fullName'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      departmentId: json['departmentId'] as String?,
      branchId: json['branchId'] as String?,
      branchCode: json['branchCode'] as String? ?? 'main',
      isOnline: json['isOnline'] as bool? ?? false,
      presenceStatus: json['presenceStatus'] as String? ?? 'offline',
      isActive: json['isActive'] as bool? ?? true,
      avatarUrl: _rawMediaUrl(json['avatarUrl']),
      lastSeen: json['lastSeen'] is String
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      lastActiveAt: json['lastActiveAt'] is String
          ? DateTime.tryParse(json['lastActiveAt'] as String)
          : null,
      permissions: permissionsJson.map(
        (key, value) => MapEntry(key, value == true),
      ),
      chatPreferences: ChatPreferences.fromJson(chatPrefsJson),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'fullName': fullName,
      'role': role,
      'departmentId': departmentId,
      'branchId': branchId,
      'branchCode': branchCode,
      'isOnline': isOnline,
      'presenceStatus': presenceStatus,
      'isActive': isActive,
      'avatarUrl': avatarUrl,
      'lastSeen': lastSeen?.toIso8601String(),
      'lastActiveAt': lastActiveAt?.toIso8601String(),
      'permissions': permissions,
      'chatPreferences': chatPreferences.toJson(),
    };
  }
}

String? _rawMediaUrl(Object? value) {
  final raw = value?.toString().trim();
  return raw == null || raw.isEmpty ? null : raw;
}

class ChatPreferences {
  static const defaults = ChatPreferences(
    themeId: 'system',
    wallpaperId: 'default',
    customTheme: ChatCustomTheme.defaults,
    disableAnimatedEmojis: false,
  );

  const ChatPreferences({
    required this.themeId,
    required this.wallpaperId,
    required this.customTheme,
    this.disableAnimatedEmojis = false,
  });

  final String themeId;
  final String wallpaperId;
  final ChatCustomTheme customTheme;
  final bool disableAnimatedEmojis;

  factory ChatPreferences.fromJson(Map<String, dynamic>? json) {
    return ChatPreferences(
      themeId: (json?['themeId'] as String?)?.trim().isNotEmpty == true
          ? (json!['themeId'] as String).trim()
          : 'system',
      wallpaperId: (json?['wallpaperId'] as String?)?.trim().isNotEmpty == true
          ? (json!['wallpaperId'] as String).trim()
          : 'default',
      customTheme: ChatCustomTheme.fromJson(
        json?['customTheme'] as Map<String, dynamic>?,
      ),
      disableAnimatedEmojis: json?['disableAnimatedEmojis'] == true,
    );
  }

  ChatPreferences copyWith({
    String? themeId,
    String? wallpaperId,
    ChatCustomTheme? customTheme,
    bool? disableAnimatedEmojis,
  }) {
    return ChatPreferences(
      themeId: themeId ?? this.themeId,
      wallpaperId: wallpaperId ?? this.wallpaperId,
      customTheme: customTheme ?? this.customTheme,
      disableAnimatedEmojis: disableAnimatedEmojis ?? this.disableAnimatedEmojis,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeId': themeId,
    'wallpaperId': wallpaperId,
    'customTheme': customTheme.toJson(),
    'disableAnimatedEmojis': disableAnimatedEmojis,
  };
}

class ChatCustomTheme {
  static const defaults = ChatCustomTheme(
    accentColorHex: '#3390EC',
    outgoingBubbleColorHexes: <String>['#5BA9FF', '#2F8CFF'],
    incomingBubbleColorHex: '#182533',
    wallpaperColorHexes: <String>['#0E1621', '#111B26', '#17212B'],
  );

  const ChatCustomTheme({
    required this.accentColorHex,
    required this.outgoingBubbleColorHexes,
    required this.incomingBubbleColorHex,
    required this.wallpaperColorHexes,
  });

  final String accentColorHex;
  final List<String> outgoingBubbleColorHexes;
  final String incomingBubbleColorHex;
  final List<String> wallpaperColorHexes;

  factory ChatCustomTheme.fromJson(Map<String, dynamic>? json) {
    final outgoing = _normalizeColorHexList(
      json?['outgoingBubbleColorHexes'],
      fallback: defaults.outgoingBubbleColorHexes,
      maxLength: 2,
    );
    final wallpaper = _normalizeColorHexList(
      json?['wallpaperColorHexes'],
      fallback: defaults.wallpaperColorHexes,
      minLength: 2,
      maxLength: 4,
    );
    return ChatCustomTheme(
      accentColorHex: _normalizeColorHex(
        json?['accentColorHex'],
        fallback: defaults.accentColorHex,
      ),
      outgoingBubbleColorHexes: outgoing,
      incomingBubbleColorHex: _normalizeColorHex(
        json?['incomingBubbleColorHex'],
        fallback: defaults.incomingBubbleColorHex,
      ),
      wallpaperColorHexes: wallpaper,
    );
  }

  ChatCustomTheme copyWith({
    String? accentColorHex,
    List<String>? outgoingBubbleColorHexes,
    String? incomingBubbleColorHex,
    List<String>? wallpaperColorHexes,
  }) {
    return ChatCustomTheme(
      accentColorHex: _normalizeColorHex(
        accentColorHex,
        fallback: this.accentColorHex,
      ),
      outgoingBubbleColorHexes: _normalizeColorHexList(
        outgoingBubbleColorHexes,
        fallback: this.outgoingBubbleColorHexes,
        maxLength: 2,
      ),
      incomingBubbleColorHex: _normalizeColorHex(
        incomingBubbleColorHex,
        fallback: this.incomingBubbleColorHex,
      ),
      wallpaperColorHexes: _normalizeColorHexList(
        wallpaperColorHexes,
        fallback: this.wallpaperColorHexes,
        minLength: 2,
        maxLength: 4,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'accentColorHex': accentColorHex,
    'outgoingBubbleColorHexes': outgoingBubbleColorHexes,
    'incomingBubbleColorHex': incomingBubbleColorHex,
    'wallpaperColorHexes': wallpaperColorHexes,
  };
}

String _normalizeColorHex(Object? raw, {required String fallback}) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) {
    return fallback;
  }
  final normalized = value.startsWith('#') ? value : '#$value';
  final hex = normalized.substring(1);
  final isValid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex);
  return isValid ? '#${hex.toUpperCase()}' : fallback;
}

List<String> _normalizeColorHexList(
  Object? raw, {
  required List<String> fallback,
  int minLength = 1,
  int maxLength = 4,
}) {
  final values = switch (raw) {
    final List<dynamic> list =>
      list
          .map((entry) => _normalizeColorHex(entry, fallback: ''))
          .where((entry) => entry.isNotEmpty)
          .take(maxLength)
          .toList(),
    _ => const <String>[],
  };
  if (values.length < minLength) {
    return fallback;
  }
  return values;
}
