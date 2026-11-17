class NotificationTone {
  const NotificationTone({
    required this.id,
    required this.label,
    this.assetPath,
    this.isSilent = false,
  });

  final String id;
  final String label;
  final String? assetPath;
  final bool isSilent;

  static const defaultTone = NotificationTone(
    id: 'default',
    label: 'افتراضي',
    assetPath: 'assets/notification_sounds/default_tone.wav',
  );

  static const chimeTone = NotificationTone(
    id: 'chime',
    label: 'نغمة رنين',
    assetPath: 'assets/notification_sounds/chime_tone.wav',
  );

  static const alertTone = NotificationTone(
    id: 'alert',
    label: 'تنبيه هادئ',
    assetPath: 'assets/notification_sounds/alert_tone.wav',
  );

  static const silentTone = NotificationTone(
    id: 'silent',
    label: 'بدون صوت',
    isSilent: true,
  );

  static const values = [defaultTone, chimeTone, alertTone, silentTone];

  static NotificationTone fromId(String? id) {
    return values.firstWhere(
      (tone) => tone.id == id,
      orElse: () => defaultTone,
    );
  }
}

enum NotificationDisplayMode {
  all(
    id: 'all',
    label: 'إظهار الإشعار كاملاً',
    description: 'صوت التنبيه مع ظهور اسم الراسل ومحتوى الرسالة على جانب الشاشة.',
  ),
  hideDetails(
    id: 'hide_details',
    label: 'إخفاء تفاصيل الرسالة',
    description: 'صوت التنبيه مع إشعار مختصر (رسالة جديدة) بدون الاسم أو النص.',
  ),
  soundOnly(
    id: 'sound_only',
    label: 'صوت التنبيه فقط (بدون ظهور في الجنب)',
    description: 'تشغيل صوت التنبيه فقط دون ظهور أي رسائل منبثقة على جانب الشاشة.',
  );

  const NotificationDisplayMode({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  static const defaultMode = NotificationDisplayMode.all;

  static NotificationDisplayMode fromId(String? id) {
    for (final mode in values) {
      if (mode.id == id) return mode;
    }
    return defaultMode;
  }
}

class UserPreferences {
  const UserPreferences({
    required this.enterSendsMessage,
    required this.autoSaveAfterScan,
    required this.scanSaveDirectoryPath,
    required this.localStorageDirectoryPath,
    required this.preferredPrinterName,
    required this.notificationToneId,
    this.notificationDisplayModeId = 'all',
    this.notificationsEnabled = true,
    this.messageNotificationsEnabled = true,
    this.messageVibrate = true,
    this.messagePreview = true,
    this.groupNotificationsEnabled = true,
    this.groupToneId = 'default',
    this.groupVibrate = true,
    this.groupPreview = true,
    this.groupNotificationsByChat = true,
    this.inAppBanners = true,
    this.reactionNotifications = true,
    this.autoClearOnOpen = true,
  });

  factory UserPreferences.defaults() {
    return const UserPreferences(
      enterSendsMessage: false,
      autoSaveAfterScan: false,
      scanSaveDirectoryPath: null,
      localStorageDirectoryPath: null,
      preferredPrinterName: null,
      notificationToneId: 'default',
      notificationDisplayModeId: 'all',
      notificationsEnabled: true,
      messageNotificationsEnabled: true,
      messageVibrate: true,
      messagePreview: true,
      groupNotificationsEnabled: true,
      groupToneId: 'default',
      groupVibrate: true,
      groupPreview: true,
      groupNotificationsByChat: true,
      inAppBanners: true,
      reactionNotifications: true,
      autoClearOnOpen: true,
    );
  }

  final bool enterSendsMessage;
  final bool autoSaveAfterScan;
  final String? scanSaveDirectoryPath;
  final String? localStorageDirectoryPath;
  final String? preferredPrinterName;
  final String notificationToneId;
  final String notificationDisplayModeId;
  final bool notificationsEnabled;
  final bool messageNotificationsEnabled;
  final bool messageVibrate;
  final bool messagePreview;
  final bool groupNotificationsEnabled;
  final String groupToneId;
  final bool groupVibrate;
  final bool groupPreview;
  final bool groupNotificationsByChat;
  final bool inAppBanners;
  final bool reactionNotifications;
  final bool autoClearOnOpen;

  String get messageToneId => notificationToneId;

  NotificationDisplayMode get notificationDisplayMode =>
      NotificationDisplayMode.fromId(notificationDisplayModeId);

  NotificationTone get notificationTone =>
      NotificationTone.fromId(notificationToneId);

  NotificationTone get messageTone =>
      NotificationTone.fromId(notificationToneId);

  NotificationTone get groupTone =>
      NotificationTone.fromId(groupToneId);

  UserPreferences copyWith({
    bool? enterSendsMessage,
    bool? autoSaveAfterScan,
    String? scanSaveDirectoryPath,
    bool clearScanSaveDirectoryPath = false,
    String? localStorageDirectoryPath,
    bool clearLocalStorageDirectoryPath = false,
    String? preferredPrinterName,
    bool clearPreferredPrinterName = false,
    String? notificationToneId,
    String? notificationDisplayModeId,
    bool? notificationsEnabled,
    bool? messageNotificationsEnabled,
    bool? messageVibrate,
    bool? messagePreview,
    bool? groupNotificationsEnabled,
    String? groupToneId,
    bool? groupVibrate,
    bool? groupPreview,
    bool? groupNotificationsByChat,
    bool? inAppBanners,
    bool? reactionNotifications,
    bool? autoClearOnOpen,
  }) {
    return UserPreferences(
      enterSendsMessage: enterSendsMessage ?? this.enterSendsMessage,
      autoSaveAfterScan: autoSaveAfterScan ?? this.autoSaveAfterScan,
      scanSaveDirectoryPath: clearScanSaveDirectoryPath
          ? null
          : (scanSaveDirectoryPath ?? this.scanSaveDirectoryPath),
      localStorageDirectoryPath: clearLocalStorageDirectoryPath
          ? null
          : (localStorageDirectoryPath ?? this.localStorageDirectoryPath),
      preferredPrinterName: clearPreferredPrinterName
          ? null
          : (preferredPrinterName ?? this.preferredPrinterName),
      notificationToneId: notificationToneId ?? this.notificationToneId,
      notificationDisplayModeId:
          notificationDisplayModeId ?? this.notificationDisplayModeId,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      messageNotificationsEnabled:
          messageNotificationsEnabled ?? this.messageNotificationsEnabled,
      messageVibrate: messageVibrate ?? this.messageVibrate,
      messagePreview: messagePreview ?? this.messagePreview,
      groupNotificationsEnabled:
          groupNotificationsEnabled ?? this.groupNotificationsEnabled,
      groupToneId: groupToneId ?? this.groupToneId,
      groupVibrate: groupVibrate ?? this.groupVibrate,
      groupPreview: groupPreview ?? this.groupPreview,
      groupNotificationsByChat:
          groupNotificationsByChat ?? this.groupNotificationsByChat,
      inAppBanners: inAppBanners ?? this.inAppBanners,
      reactionNotifications:
          reactionNotifications ?? this.reactionNotifications,
      autoClearOnOpen: autoClearOnOpen ?? this.autoClearOnOpen,
    );
  }
}
