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

class UserPreferences {
  const UserPreferences({
    required this.enterSendsMessage,
    required this.autoSaveAfterScan,
    required this.scanSaveDirectoryPath,
    required this.localStorageDirectoryPath,
    required this.preferredPrinterName,
    required this.notificationToneId,
  });

  factory UserPreferences.defaults() {
    return const UserPreferences(
      enterSendsMessage: false,
      autoSaveAfterScan: false,
      scanSaveDirectoryPath: null,
      localStorageDirectoryPath: null,
      preferredPrinterName: null,
      notificationToneId: 'default',
    );
  }

  final bool enterSendsMessage;
  final bool autoSaveAfterScan;
  final String? scanSaveDirectoryPath;
  final String? localStorageDirectoryPath;
  final String? preferredPrinterName;
  final String notificationToneId;

  NotificationTone get notificationTone =>
      NotificationTone.fromId(notificationToneId);

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
    );
  }
}
