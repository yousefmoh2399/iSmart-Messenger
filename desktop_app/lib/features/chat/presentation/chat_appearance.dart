import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/models/app_user.dart';

class ChatThemeOption {
  const ChatThemeOption({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.outgoingLightColor,
    required this.incomingLightColor,
    required this.outgoingDarkColor,
    required this.incomingDarkColor,
    this.badge,
    this.hasSnowCaps = false,
  });

  final String id;
  final String title;
  final String description;
  final Color color;
  final Color outgoingLightColor;
  final Color incomingLightColor;
  final Color outgoingDarkColor;
  final Color incomingDarkColor;
  final String? badge;
  final bool hasSnowCaps;
}

class ChatWallpaperOption {
  const ChatWallpaperOption({
    required this.id,
    required this.title,
    required this.category,
    required this.previewColors,
    required this.lightColors,
    required this.darkColors,
    this.hasDoodles = true,
  });

  final String id;
  final String title;
  final String category; // 'telegram', 'comfort', 'whatsapp', 'gradient'
  final List<Color> previewColors;
  final List<Color> lightColors;
  final List<Color> darkColors;
  final bool hasDoodles;
}

class ChatResolvedAppearance {
  const ChatResolvedAppearance({
    required this.accent,
    required this.outgoingBubbleColors,
    required this.incomingBubbleColor,
    required this.outgoingTextColor,
    required this.incomingTextColor,
    required this.outgoingBorderColor,
    required this.incomingBorderColor,
    required this.outgoingReplyColor,
    required this.incomingReplyColor,
    required this.wallpaperColors,
    required this.patternColor,
    required this.sparkleColor,
    required this.isDarkVariant,
    this.showDoodles = true,
    this.hasSnowCaps = false,
  });

  final Color accent;
  final List<Color> outgoingBubbleColors;
  final Color incomingBubbleColor;
  final Color outgoingTextColor;
  final Color incomingTextColor;
  final Color outgoingBorderColor;
  final Color incomingBorderColor;
  final Color outgoingReplyColor;
  final Color incomingReplyColor;
  final List<Color> wallpaperColors;
  final Color patternColor;
  final Color sparkleColor;
  final bool isDarkVariant;
  final bool showDoodles;
  final bool hasSnowCaps;

  bool get hasOutgoingGradient =>
      outgoingBubbleColors.length > 1 &&
      outgoingBubbleColors.any((entry) => entry != outgoingBubbleColors.first);
}

class ChatAppearanceCatalog {
  static const themes = <ChatThemeOption>[
    ChatThemeOption(
      id: 'festive_winter',
      title: 'رأس السنة والجليد ❄️',
      description: 'أجواء احتفالية شتوية مع تراكم الثلج ورقاقات الجليد الأنيقة على حواف الرسائل',
      color: Color(0xFF0284C7),
      outgoingLightColor: Color(0xFF0284C7),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF0284C7),
      incomingDarkColor: Color(0xFF1E293B),
      badge: 'احتفالي رأس السنة ❄️',
      hasSnowCaps: true,
    ),
    ChatThemeOption(
      id: 'festive_halloween',
      title: 'هالوين الاحتفالي 🎃',
      description: 'أجواء خريفية احتفالية دافئة بألوان اليقطين المتوهجة والظلال البنفسجية الهادئة',
      color: Color(0xFFEA580C),
      outgoingLightColor: Color(0xFFEA580C),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFFEA580C),
      incomingDarkColor: Color(0xFF261B31),
      badge: 'احتفالي الهالوين 🎃',
      hasSnowCaps: false,
    ),
    ChatThemeOption(
      id: 'whatsapp',
      title: 'واتساب الرسمي',
      description: 'فقاعات خضراء كلاسيكية مع خلفية البيج ورسومات واتساب',
      color: Color(0xFF00A884),
      outgoingLightColor: Color(0xFFD9FDD3),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF005C4B),
      incomingDarkColor: Color(0xFF202C33),
      badge: 'الأكثر طلباً',
    ),
    ChatThemeOption(
      id: 'telegram_night',
      title: 'ليل تلجرام',
      description: 'المظهر الليلي الفاخر لتلجرام بدرجات كحلي وأزرق متوهج فائق الراحة للعين',
      color: Color(0xFF2AABEE),
      outgoingLightColor: Color(0xFFD8EEFE),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF2B5278),
      incomingDarkColor: Color(0xFF182533),
      badge: 'Telegram Dark',
    ),
    ChatThemeOption(
      id: 'telegram_arctic',
      title: 'أزرق قطبي',
      description: 'مظهر تلجرام العصري الأنيق بتدرج أزرق ناصع وفقاعات انسيابية مريحة للبصر',
      color: Color(0xFF229ED9),
      outgoingLightColor: Color(0xFF229ED9),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF1D78B0),
      incomingDarkColor: Color(0xFF1C2733),
      badge: 'Telegram Pro',
    ),
    ChatThemeOption(
      id: 'desert_warmth',
      title: 'صحراء دافئة',
      description: 'مستوحى من سمة صحراء تلجرام الكهرمانية بدون إشعاع أزرق مجهد لإراحة العين التامة',
      color: Color(0xFFD97706),
      outgoingLightColor: Color(0xFFEEDCC7),
      incomingLightColor: Color(0xFFFFFDF9),
      outgoingDarkColor: Color(0xFF4A3728),
      incomingDarkColor: Color(0xFF241D17),
      badge: 'مريح للعين 👁️',
    ),
    ChatThemeOption(
      id: 'sage_harmony',
      title: 'أعشاب المريمية',
      description: 'ألوان نباتية ترابية مهدئة للأعصاب مصممة خصيصاً لساعات العمل الطويلة وقراءة المحادثات',
      color: Color(0xFF5F8D76),
      outgoingLightColor: Color(0xFFDCECE1),
      incomingLightColor: Color(0xFFF9FCFA),
      outgoingDarkColor: Color(0xFF1E3A2B),
      incomingDarkColor: Color(0xFF15261D),
      badge: 'حماية العين 🌿',
    ),
    ChatThemeOption(
      id: 'classic',
      title: 'تلجرام كلاسيك',
      description: 'مظهر تلجرام الشهير بفقاعة خضراء هادئة وأزرق ناصع',
      color: Color(0xFF3390EC),
      outgoingLightColor: Color(0xFFEFFDDE),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF2B5278),
      incomingDarkColor: Color(0xFF182533),
      badge: 'Telegram Classic',
    ),
    ChatThemeOption(
      id: 'ios',
      title: 'رسائل آبل',
      description: 'مظهر iMessage الأنيق بفقاعة زرقاء ناصعة ورمادي هادئ',
      color: Color(0xFF007AFF),
      outgoingLightColor: Color(0xFF007AFF),
      incomingLightColor: Color(0xFFE9E9EB),
      outgoingDarkColor: Color(0xFF0B84FE),
      incomingDarkColor: Color(0xFF26252A),
      badge: 'Apple iOS',
    ),
    ChatThemeOption(
      id: 'nordic_frost',
      title: 'صقيع الشمال',
      description: 'درجات رمادية مائلة للزرقة النوردية الهادئة، فخامة وتركيز بصري ممتاز',
      color: Color(0xFF64748B),
      outgoingLightColor: Color(0xFFE2E8F0),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF273544),
      incomingDarkColor: Color(0xFF182029),
      badge: 'نوردي هادئ',
    ),
    ChatThemeOption(
      id: 'blossom_mauve',
      title: 'أزهار لافندر',
      description: 'درجات الموف واللافندر الهادئة غير المتوهجة، لمسة تلجرام الفنية العصرية',
      color: Color(0xFF8B5CF6),
      outgoingLightColor: Color(0xFFEDE9FE),
      incomingLightColor: Color(0xFFFDFBFE),
      outgoingDarkColor: Color(0xFF381E48),
      incomingDarkColor: Color(0xFF201328),
      badge: 'أنيق',
    ),
    ChatThemeOption(
      id: 'mint',
      title: 'زمرد فاخر',
      description: 'درجات خضراء زمردية ملكية مريحة للعين',
      color: Color(0xFF10B981),
      outgoingLightColor: Color(0xFFD1FAE5),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF064E3B),
      incomingDarkColor: Color(0xFF14241F),
    ),
    ChatThemeOption(
      id: 'sunset',
      title: 'غروب دافئ',
      description: 'ألوان كهرمانية وذهبية دافئة مريحة للمساء',
      color: Color(0xFFF59E0B),
      outgoingLightColor: Color(0xFFFEF3C7),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF78350F),
      incomingDarkColor: Color(0xFF271F1B),
    ),
    ChatThemeOption(
      id: 'mono',
      title: 'جرافيت داكن',
      description: 'مظهر احترافي محايد لشاشات OLED وراحة العين',
      color: Color(0xFF64748B),
      outgoingLightColor: Color(0xFFE2E8F0),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF27272A),
      incomingDarkColor: Color(0xFF18181B),
      badge: 'OLED Black',
    ),
    ChatThemeOption(
      id: 'system',
      title: 'افتراضي التطبيق',
      description: 'يتكيف تلقائياً مع السمة العامة للتطبيق',
      color: Color(0xFF0284C7),
      outgoingLightColor: Color(0xFFDDF4FF),
      incomingLightColor: Color(0xFFFFFFFF),
      outgoingDarkColor: Color(0xFF1E3A5F),
      incomingDarkColor: Color(0xFF182533),
    ),
    ChatThemeOption(
      id: 'custom',
      title: 'تخصيص يدوي',
      description: 'اختر بحرية ألوان الرسائل والخلفية بالكامل',
      color: Color(0xFF8B5CF6),
      outgoingLightColor: Color(0xFF5BA9FF),
      incomingLightColor: Color(0xFFF1F5F9),
      outgoingDarkColor: Color(0xFF2F8CFF),
      incomingDarkColor: Color(0xFF1E293B),
    ),
  ];

  static const wallpapers = <ChatWallpaperOption>[
    // 0. Festive & Seasons
    ChatWallpaperOption(
      id: 'wp_winter_snow',
      title: 'جليد وشتاء رأس السنة ❄️',
      category: 'festive',
      previewColors: [Color(0xFF0284C7), Color(0xFFBAE6FD)],
      lightColors: [Color(0xFFE0F2FE), Color(0xFFF0F9FF)],
      darkColors: [Color(0xFF082F49), Color(0xFF0C4A6E)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wp_halloween',
      title: 'يقطين الهالوين 🎃',
      category: 'festive',
      previewColors: [Color(0xFFEA580C), Color(0xFF261B31)],
      lightColors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
      darkColors: [Color(0xFF1F122B), Color(0xFF2E1065)],
      hasDoodles: true,
    ),

    // 1. Telegram Originals
    ChatWallpaperOption(
      id: 'tg_classic',
      title: 'سماء تلجرام',
      category: 'telegram',
      previewColors: [Color(0xFF2AABEE), Color(0xFF229ED9)],
      lightColors: [Color(0xFFE4EDF5), Color(0xFFD6E3EF)],
      darkColors: [Color(0xFF0E1621), Color(0xFF17212B)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'tg_night',
      title: 'ليل تلجرام الكحلي',
      category: 'telegram',
      previewColors: [Color(0xFF17212B), Color(0xFF0E1621)],
      lightColors: [Color(0xFFD9E2EC), Color(0xFFBCCCDC)],
      darkColors: [Color(0xFF0A1017), Color(0xFF121B24)],
      hasDoodles: true,
    ),

    // 2. Eye Comfort & Protection
    ChatWallpaperOption(
      id: 'tg_desert',
      title: 'كثبان الصحراء الدافئة',
      category: 'comfort',
      previewColors: [Color(0xFFE2C9AC), Color(0xFFD6BA99)],
      lightColors: [Color(0xFFF7F2E9), Color(0xFFEDE4D5)],
      darkColors: [Color(0xFF1C1712), Color(0xFF261D17)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'tg_sage',
      title: 'حديقة المريمية الهادئة',
      category: 'comfort',
      previewColors: [Color(0xFF5F8D76), Color(0xFF3F6352)],
      lightColors: [Color(0xFFEBF4EE), Color(0xFFDEEDE3)],
      darkColors: [Color(0xFF0D1712), Color(0xFF13221A)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'grad_eye_comfort',
      title: 'حماية العين (بدون أزرق)',
      category: 'comfort',
      previewColors: [Color(0xFFF7F4EC), Color(0xFFEFE8DA)],
      lightColors: [Color(0xFFF7F4EC), Color(0xFFEFE8DA)],
      darkColors: [Color(0xFF1C1917), Color(0xFF241F1A)],
      hasDoodles: false,
    ),

    // 3. WhatsApp Classics
    ChatWallpaperOption(
      id: 'wa_classic',
      title: 'البيج الكلاسيكي',
      category: 'whatsapp',
      previewColors: [Color(0xFFEFEAE2), Color(0xFFE6DFD5)],
      lightColors: [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
      darkColors: [Color(0xFF0B141A), Color(0xFF0B141A)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_emerald',
      title: 'زمرد واتساب',
      category: 'whatsapp',
      previewColors: [Color(0xFF00A884), Color(0xFF054640)],
      lightColors: [Color(0xFFD5F3E4), Color(0xFFE2F8EE)],
      darkColors: [Color(0xFF053E31), Color(0xFF084D3E)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_midnight',
      title: 'أزرق ليلي',
      category: 'whatsapp',
      previewColors: [Color(0xFF1F2C40), Color(0xFF0C131F)],
      lightColors: [Color(0xFFDCEAF7), Color(0xFFEDF4FA)],
      darkColors: [Color(0xFF0C131F), Color(0xFF141F30)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_sand',
      title: 'رمال دافئة',
      category: 'whatsapp',
      previewColors: [Color(0xFFF7F3EB), Color(0xFFEDE5D8)],
      lightColors: [Color(0xFFF7F3EB), Color(0xFFF2ECE1)],
      darkColors: [Color(0xFF1E1B18), Color(0xFF282420)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_slate',
      title: 'رمادي أنيق',
      category: 'whatsapp',
      previewColors: [Color(0xFFECEFF1), Color(0xFFCFD8DC)],
      lightColors: [Color(0xFFECEFF1), Color(0xFFE4E8EB)],
      darkColors: [Color(0xFF141C22), Color(0xFF1B242B)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_mint',
      title: 'نسيم النعناع',
      category: 'whatsapp',
      previewColors: [Color(0xFFDFF7EF), Color(0xFFC7F0E1)],
      lightColors: [Color(0xFFDFF7EF), Color(0xFFEEFAF4)],
      darkColors: [Color(0xFF10261F), Color(0xFF16332A)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_sky',
      title: 'سماء هادئة',
      category: 'whatsapp',
      previewColors: [Color(0xFFBAE6FD), Color(0xFF7DD3FC)],
      lightColors: [Color(0xFFE0F2FE), Color(0xFFEFF8FF)],
      darkColors: [Color(0xFF0C2233), Color(0xFF102D42)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_lilac',
      title: 'لافندر ناعم',
      category: 'whatsapp',
      previewColors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
      lightColors: [Color(0xFFEDE9FE), Color(0xFFF5F2FE)],
      darkColors: [Color(0xFF1C162E), Color(0xFF251E3C)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_rose',
      title: 'وردي هادئ',
      category: 'whatsapp',
      previewColors: [Color(0xFFFBCFE8), Color(0xFFF472B6)],
      lightColors: [Color(0xFFFCE7F3), Color(0xFFFFF1F7)],
      darkColors: [Color(0xFF2B1420), Color(0xFF381B2B)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_peach',
      title: 'شروق خوخي',
      category: 'whatsapp',
      previewColors: [Color(0xFFFFEDD5), Color(0xFFFED7AA)],
      lightColors: [Color(0xFFFFEDD5), Color(0xFFFFF6EB)],
      darkColors: [Color(0xFF2A1B10), Color(0xFF382516)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_forest',
      title: 'غابة خضراء',
      category: 'whatsapp',
      previewColors: [Color(0xFF064E3B), Color(0xFF022C22)],
      lightColors: [Color(0xFFE3F7E9), Color(0xFFF0FDF4)],
      darkColors: [Color(0xFF0A2218), Color(0xFF0F2E21)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_coffee',
      title: 'موكا دافئة',
      category: 'whatsapp',
      previewColors: [Color(0xFF78350F), Color(0xFF451A03)],
      lightColors: [Color(0xFFF5EBE1), Color(0xFFFAF3EC)],
      darkColors: [Color(0xFF231812), Color(0xFF2E2018)],
      hasDoodles: true,
    ),
    ChatWallpaperOption(
      id: 'wa_dark_oled',
      title: 'واتساب OLED',
      category: 'whatsapp',
      previewColors: [Color(0xFF0B141A), Color(0xFF000000)],
      lightColors: [Color(0xFFE5DDD5), Color(0xFFECE5DD)],
      darkColors: [Color(0xFF0B141A), Color(0xFF070B0E)],
      hasDoodles: true,
    ),

    // 4. Modern Gradients
    ChatWallpaperOption(
      id: 'grad_deep_cosmos',
      title: 'سديم فضائي عميق',
      category: 'gradient',
      previewColors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
      lightColors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE)],
      darkColors: [Color(0xFF0D0D1A), Color(0xFF14142B)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_aurora',
      title: 'شفق قطبي',
      category: 'gradient',
      previewColors: [Color(0xFF11998E), Color(0xFF38EF7D)],
      lightColors: [Color(0xFFD4FC79), Color(0xFF96E6A1)],
      darkColors: [Color(0xFF09203F), Color(0xFF1B4965)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_ocean',
      title: 'أعماق المحيط',
      category: 'gradient',
      previewColors: [Color(0xFF2193B0), Color(0xFF6DD5ED)],
      lightColors: [Color(0xFFC6E7FF), Color(0xFF99D3FF)],
      darkColors: [Color(0xFF0F2027), Color(0xFF203A43)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_sunset',
      title: 'تدرج الغروب',
      category: 'gradient',
      previewColors: [Color(0xFFFF512F), Color(0xFFDD2476)],
      lightColors: [Color(0xFFFFE2D2), Color(0xFFFFD1DC)],
      darkColors: [Color(0xFF3D1635), Color(0xFF5A1E38)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_purple',
      title: 'أرجواني ملكي',
      category: 'gradient',
      previewColors: [Color(0xFF8A2387), Color(0xFFE94057)],
      lightColors: [Color(0xFFF3E5F5), Color(0xFFEDE7F6)],
      darkColors: [Color(0xFF1F1135), Color(0xFF2F174A)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_nordic',
      title: 'سحر الشمال',
      category: 'gradient',
      previewColors: [Color(0xFF3A6073), Color(0xFF3A7BD5)],
      lightColors: [Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
      darkColors: [Color(0xFF1E293B), Color(0xFF0F172A)],
      hasDoodles: false,
    ),
    ChatWallpaperOption(
      id: 'grad_oled',
      title: 'أسود فاحم OLED',
      category: 'gradient',
      previewColors: [Color(0xFF1E2124), Color(0xFF000000)],
      lightColors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
      darkColors: [Color(0xFF000000), Color(0xFF080808)],
      hasDoodles: false,
    ),
  ];

  static const customAccentSwatches = <Color>[
    Color(0xFF00A884), // WhatsApp Green
    Color(0xFF2AABEE), // Telegram Sky
    Color(0xFF229ED9), // Telegram Blue
    Color(0xFF007AFF), // Apple Blue
    Color(0xFF5F8D76), // Sage Harmony
    Color(0xFFD97706), // Desert Amber
    Color(0xFF10B981), // Emerald
    Color(0xFF8B5CF6), // Violet / Mauve
    Color(0xFFEC4899), // Pink
    Color(0xFF64748B), // Slate
  ];

  static const customBubbleSwatches = <Color>[
    Color(0xFFD9FDD3), // WhatsApp light outgoing
    Color(0xFF005C4B), // WhatsApp dark outgoing
    Color(0xFF2AABEE), // Telegram Vibrant Blue
    Color(0xFF2B5278), // Telegram Dark Outgoing
    Color(0xFF182533), // Telegram Dark Incoming
    Color(0xFF007AFF), // Apple Blue
    Color(0xFFE9E9EB), // Apple Light Gray
    Color(0xFFEEDCC7), // Desert Warmth Light
    Color(0xFF4A3728), // Desert Warmth Dark
    Color(0xFFDCECE1), // Sage Harmony Light
    Color(0xFF1E3A2B), // Sage Harmony Dark
    Color(0xFFEDE9FE), // Mauve Light
    Color(0xFF381E48), // Mauve Dark
    Color(0xFF27272A), // Mono Dark
    Color(0xFFFFFFFF), // Pure White
  ];

  static const customWallpaperPalettes = <List<Color>>[
    [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
    [Color(0xFF0B141A), Color(0xFF0B141A)],
    [Color(0xFFE4EDF5), Color(0xFFD6E3EF)],
    [Color(0xFF0E1621), Color(0xFF17212B)],
    [Color(0xFFF7F2E9), Color(0xFFEDE4D5)],
    [Color(0xFF1C1712), Color(0xFF261D17)],
    [Color(0xFFEBF4EE), Color(0xFFDEEDE3)],
    [Color(0xFF0D1712), Color(0xFF13221A)],
    [Color(0xFFD5F3E4), Color(0xFFE2F8EE)],
    [Color(0xFF053E31), Color(0xFF084D3E)],
  ];

  static bool usesSystemMode(String themeId) => themeId == 'system';

  static bool usesCustomTheme(String themeId) => themeId == 'custom';

  static ChatThemeOption themeById(String themeId) {
    for (final entry in themes) {
      if (entry.id == themeId) return entry;
    }
    return themes.first;
  }

  static ChatWallpaperOption wallpaperById(String wallpaperId) {
    for (final entry in wallpapers) {
      if (entry.id == wallpaperId) return entry;
    }
    return wallpapers.first;
  }

  static ChatResolvedAppearance resolveAppearance({
    required ChatPreferences preferences,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    if (usesCustomTheme(preferences.themeId)) {
      return _resolveCustomAppearance(
        preferences: preferences,
        isDark: isDark,
      );
    }
    if (usesSystemMode(preferences.themeId)) {
      return _resolveSystemAppearance(
        preferences: preferences,
        isDark: isDark,
        colorScheme: colorScheme,
      );
    }
    return _resolvePresetAppearance(
      preferences: preferences,
      isDark: isDark,
    );
  }

  static ChatResolvedAppearance _resolveSystemAppearance({
    required ChatPreferences preferences,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    final wallpaperColors = _wallpaperColorsFor(
      wallpaperId: preferences.wallpaperId,
      isDark: isDark,
      fallback: isDark
          ? [const Color(0xFF0B141A), const Color(0xFF070B0E)]
          : [const Color(0xFFEFEAE2), const Color(0xFFE6DFD5)],
      customTheme: preferences.customTheme,
    );

    final patternColor = _doodleColorFor(
      wallpaperColors: wallpaperColors,
      isDark: isDark,
    );

    final outgoingBubble = isDark
        ? [colorScheme.primaryContainer, colorScheme.primary.withValues(alpha: 0.85)]
        : [colorScheme.primary.withValues(alpha: 0.16)];

    final incomingBubble = isDark
        ? const Color(0xFF1E2836)
        : colorScheme.surface;

    return ChatResolvedAppearance(
      accent: colorScheme.primary,
      outgoingBubbleColors: outgoingBubble,
      incomingBubbleColor: incomingBubble,
      outgoingTextColor: isDark
          ? colorScheme.onPrimaryContainer
          : colorScheme.onSurface,
      incomingTextColor: isDark
          ? const Color(0xFFF1F5F9)
          : colorScheme.onSurface,
      outgoingBorderColor: isDark
          ? colorScheme.primary.withValues(alpha: 0.3)
          : colorScheme.primary.withValues(alpha: 0.25),
      incomingBorderColor: isDark
          ? const Color(0xFF243140)
          : colorScheme.outlineVariant.withValues(alpha: 0.3),
      outgoingReplyColor: isDark
          ? const Color(0xFF1E3A5F)
          : const Color(0xFFECF7FF),
      incomingReplyColor: isDark
          ? const Color(0xFF223446)
          : const Color(0xFFF8FBFE),
      wallpaperColors: wallpaperColors,
      patternColor: patternColor,
      sparkleColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : colorScheme.primary.withValues(alpha: 0.03),
      isDarkVariant: isDark,
      showDoodles: preferences.doodles,
    );
  }

  static ChatResolvedAppearance _resolvePresetAppearance({
    required ChatPreferences preferences,
    required bool isDark,
  }) {
    final wallpaperColors = _wallpaperColorsFor(
      wallpaperId: preferences.wallpaperId,
      isDark: isDark,
      fallback: _defaultWallpaperForTheme(preferences.themeId, isDark),
      customTheme: preferences.customTheme,
    );

    final patternColor = _doodleColorFor(
      wallpaperColors: wallpaperColors,
      isDark: isDark,
    );

    // 0. Festive Winter Snow (New Year & Winter with Snow Caps)
    if (preferences.themeId == 'festive_winter') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF0284C7),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF0369A1), Color(0xFF0284C7)]
            : const [Color(0xFF0284C7), Color(0xFF38BDF8)],
        incomingBubbleColor: isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: Colors.white,
        incomingTextColor: isDark
            ? const Color(0xFFF1F5F9)
            : const Color(0xFF0F172A),
        outgoingBorderColor: isDark
            ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
            : const Color(0xFFBAE6FD),
        incomingBorderColor: isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF075985)
            : const Color(0xFF0284C7).withValues(alpha: 0.25),
        incomingReplyColor: isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF0F9FF),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.04),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
        hasSnowCaps: true,
      );
    }

    // 0b. Festive Halloween Spooky Theme
    if (preferences.themeId == 'festive_halloween') {
      return ChatResolvedAppearance(
        accent: const Color(0xFFEA580C),
        outgoingBubbleColors: isDark
            ? const [Color(0xFFC2410C), Color(0xFFEA580C)]
            : const [Color(0xFFEA580C), Color(0xFFFB923C)],
        incomingBubbleColor: isDark
            ? const Color(0xFF261B31)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: Colors.white,
        incomingTextColor: isDark
            ? const Color(0xFFFDE047)
            : const Color(0xFF1F122B),
        outgoingBorderColor: isDark
            ? const Color(0xFFFB923C).withValues(alpha: 0.4)
            : const Color(0xFFFED7AA),
        incomingBorderColor: isDark
            ? const Color(0xFF3B264E)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF9A3412)
            : const Color(0xFFEA580C).withValues(alpha: 0.25),
        incomingReplyColor: isDark
            ? const Color(0xFF191022)
            : const Color(0xFFFFF7ED),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.06 : 0.03),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
        hasSnowCaps: false,
      );
    }

    // 1. WhatsApp Official Theme
    if (preferences.themeId == 'whatsapp') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF00A884),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF005C4B)]
            : const [Color(0xFFD9FDD3)],
        incomingBubbleColor: isDark
            ? const Color(0xFF202C33)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFE9EDEF)
            : const Color(0xFF111B21),
        incomingTextColor: isDark
            ? const Color(0xFFE9EDEF)
            : const Color(0xFF111B21),
        outgoingBorderColor: isDark
            ? const Color(0xFF02735E).withValues(alpha: 0.4)
            : const Color(0xFFC6EDB8),
        incomingBorderColor: isDark
            ? const Color(0xFF2A3942).withValues(alpha: 0.4)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF025142)
            : const Color(0xFFC7EBC1),
        incomingReplyColor: isDark
            ? const Color(0xFF1B242A)
            : const Color(0xFFF1F5F9),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.04 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 2. Telegram Night (Deep Slate & Glowing Blue)
    if (preferences.themeId == 'telegram_night') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF2AABEE),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF2B5278), Color(0xFF224466)]
            : const [Color(0xFFD8EEFE), Color(0xFFC5E3FC)],
        incomingBubbleColor: isDark
            ? const Color(0xFF182533)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFF4FBFF)
            : const Color(0xFF0C243B),
        incomingTextColor: isDark
            ? const Color(0xFFF2F5F7)
            : const Color(0xFF111827),
        outgoingBorderColor: isDark
            ? const Color(0xFF3D6B9C)
            : const Color(0xFFBCE0FD),
        incomingBorderColor: isDark
            ? const Color(0xFF243140)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF204264)
            : const Color(0xFFBEE1FD),
        incomingReplyColor: isDark
            ? const Color(0xFF203243)
            : const Color(0xFFF1F5F9),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 3. Telegram Arctic (Crisp Gradient Outgoing)
    if (preferences.themeId == 'telegram_arctic') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF229ED9),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF1D78B0), Color(0xFF186290)]
            : const [Color(0xFF2AABEE), Color(0xFF229ED9)],
        incomingBubbleColor: isDark
            ? const Color(0xFF1C2733)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: Colors.white,
        incomingTextColor: isDark
            ? const Color(0xFFF2F5F7)
            : const Color(0xFF0F172A),
        outgoingBorderColor: Colors.transparent,
        incomingBorderColor: isDark
            ? const Color(0xFF283647)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF14567F)
            : const Color(0xFF1B8BC4),
        incomingReplyColor: isDark
            ? const Color(0xFF223140)
            : const Color(0xFFF1F5F9),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 4. Desert Warmth (Eye Comfort / Zero Harsh Blue Light)
    if (preferences.themeId == 'desert_warmth') {
      return ChatResolvedAppearance(
        accent: const Color(0xFFD97706),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF4A3728), Color(0xFF3D2C1F)]
            : const [Color(0xFFEEDCC7), Color(0xFFE4CFB6)],
        incomingBubbleColor: isDark
            ? const Color(0xFF241D17)
            : const Color(0xFFFFFDF9),
        outgoingTextColor: isDark
            ? const Color(0xFFFEF3C7)
            : const Color(0xFF451A03),
        incomingTextColor: isDark
            ? const Color(0xFFF5F5F4)
            : const Color(0xFF292524),
        outgoingBorderColor: isDark
            ? const Color(0xFF6B4E37)
            : const Color(0xFFDDC3A5),
        incomingBorderColor: isDark
            ? const Color(0xFF332921)
            : const Color(0xFFEFE9DE),
        outgoingReplyColor: isDark
            ? const Color(0xFF3B2B1F)
            : const Color(0xFFDECAA9),
        incomingReplyColor: isDark
            ? const Color(0xFF2D231C)
            : const Color(0xFFF7F1E7),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 5. Sage Harmony (Eye Comfort / Botanical Rest)
    if (preferences.themeId == 'sage_harmony') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF5F8D76),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF1E3A2B), Color(0xFF162D21)]
            : const [Color(0xFFDCECE1), Color(0xFFCEE3D5)],
        incomingBubbleColor: isDark
            ? const Color(0xFF15261D)
            : const Color(0xFFF9FCFA),
        outgoingTextColor: isDark
            ? const Color(0xFFE8F5ED)
            : const Color(0xFF143521),
        incomingTextColor: isDark
            ? const Color(0xFFE8F5ED)
            : const Color(0xFF1C2D22),
        outgoingBorderColor: isDark
            ? const Color(0xFF2A523D)
            : const Color(0xFFBEDBC7),
        incomingBorderColor: isDark
            ? const Color(0xFF1F372A)
            : const Color(0xFFE3EDE6),
        outgoingReplyColor: isDark
            ? const Color(0xFF162D21)
            : const Color(0xFFBEDBC7),
        incomingReplyColor: isDark
            ? const Color(0xFF1B3125)
            : const Color(0xFFEFF5F1),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 6. Apple iOS Theme
    if (preferences.themeId == 'ios') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF007AFF),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF0B84FE)]
            : const [Color(0xFF007AFF)],
        incomingBubbleColor: isDark
            ? const Color(0xFF26252A)
            : const Color(0xFFE9E9EB),
        outgoingTextColor: Colors.white,
        incomingTextColor: isDark ? Colors.white : Colors.black,
        outgoingBorderColor: Colors.transparent,
        incomingBorderColor: isDark
            ? const Color(0xFF333338)
            : const Color(0xFFD8D8DC),
        outgoingReplyColor: isDark
            ? const Color(0xFF0868C7)
            : const Color(0xFF1A87FF),
        incomingReplyColor: isDark
            ? const Color(0xFF1F1E22)
            : const Color(0xFFDCDCE0),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.04 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 7. Telegram Classic Theme
    if (preferences.themeId == 'classic') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF3390EC),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF2B5278), Color(0xFF33628F)]
            : const [Color(0xFFEFFDDE)],
        incomingBubbleColor: isDark
            ? const Color(0xFF182533)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFF4FBFF)
            : const Color(0xFF111B21),
        incomingTextColor: isDark
            ? const Color(0xFFF2F5F7)
            : const Color(0xFF182533),
        outgoingBorderColor: isDark
            ? const Color(0xFF3D6B9C)
            : const Color(0xFFDBF2C6),
        incomingBorderColor: isDark
            ? const Color(0xFF243140)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF244668)
            : const Color(0xFFDFECC9),
        incomingReplyColor: isDark
            ? const Color(0xFF223446)
            : const Color(0xFFF8FBFE),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 8. Nordic Frost
    if (preferences.themeId == 'nordic_frost') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF64748B),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF273544), Color(0xFF1E2833)]
            : const [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
        incomingBubbleColor: isDark
            ? const Color(0xFF182029)
            : const Color(0xFFF8FAFC),
        outgoingTextColor: isDark
            ? const Color(0xFFF8FAFC)
            : const Color(0xFF1E293B),
        incomingTextColor: isDark
            ? const Color(0xFFF1F5F9)
            : const Color(0xFF0F172A),
        outgoingBorderColor: isDark
            ? const Color(0xFF3D4F63)
            : const Color(0xFFB8C5D3),
        incomingBorderColor: isDark
            ? const Color(0xFF25303D)
            : const Color(0xFFE2E8F0),
        outgoingReplyColor: isDark
            ? const Color(0xFF1E2833)
            : const Color(0xFFB8C5D3),
        incomingReplyColor: isDark
            ? const Color(0xFF202A35)
            : const Color(0xFFEDF2F7),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 9. Blossom Mauve
    if (preferences.themeId == 'blossom_mauve') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF8B5CF6),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF381E48), Color(0xFF2A1538)]
            : const [Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
        incomingBubbleColor: isDark
            ? const Color(0xFF201328)
            : const Color(0xFFFDFBFE),
        outgoingTextColor: isDark
            ? const Color(0xFFFDF4FF)
            : const Color(0xFF4C1D95),
        incomingTextColor: isDark
            ? const Color(0xFFF5E8FF)
            : const Color(0xFF2E1065),
        outgoingBorderColor: isDark
            ? const Color(0xFF552E6D)
            : const Color(0xFFC4B5FD),
        incomingBorderColor: isDark
            ? const Color(0xFF311E3E)
            : const Color(0xFFF3E8FF),
        outgoingReplyColor: isDark
            ? const Color(0xFF2B1637)
            : const Color(0xFFC4B5FD),
        incomingReplyColor: isDark
            ? const Color(0xFF291833)
            : const Color(0xFFF9F5FF),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 10. Emerald Luxury Theme
    if (preferences.themeId == 'mint') {
      return ChatResolvedAppearance(
        accent: const Color(0xFF10B981),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF064E3B), Color(0xFF047857)]
            : const [Color(0xFFD1FAE5)],
        incomingBubbleColor: isDark
            ? const Color(0xFF132B25)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFECFDF5)
            : const Color(0xFF064E3B),
        incomingTextColor: isDark
            ? const Color(0xFFECFDF5)
            : const Color(0xFF111827),
        outgoingBorderColor: isDark
            ? const Color(0xFF059669).withValues(alpha: 0.5)
            : const Color(0xFFA7F3D0),
        incomingBorderColor: isDark
            ? const Color(0xFF1F4439)
            : const Color(0xFFE5E7EB),
        outgoingReplyColor: isDark
            ? const Color(0xFF054534)
            : const Color(0xFFA7F3D0),
        incomingReplyColor: isDark
            ? const Color(0xFF17362E)
            : const Color(0xFFF3F4F6),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 11. Warm Sunset Theme
    if (preferences.themeId == 'sunset') {
      return ChatResolvedAppearance(
        accent: const Color(0xFFF59E0B),
        outgoingBubbleColors: isDark
            ? const [Color(0xFF78350F), Color(0xFF92400E)]
            : const [Color(0xFFFEF3C7)],
        incomingBubbleColor: isDark
            ? const Color(0xFF271F1B)
            : const Color(0xFFFFFFFF),
        outgoingTextColor: isDark
            ? const Color(0xFFFFFBEB)
            : const Color(0xFF78350F),
        incomingTextColor: isDark
            ? const Color(0xFFFFFBEB)
            : const Color(0xFF1C1917),
        outgoingBorderColor: isDark
            ? const Color(0xFFB45309).withValues(alpha: 0.5)
            : const Color(0xFFFDE68A),
        incomingBorderColor: isDark
            ? const Color(0xFF382A24)
            : const Color(0xFFE5E7EB),
        outgoingReplyColor: isDark
            ? const Color(0xFF6B2F0D)
            : const Color(0xFFFDE68A),
        incomingReplyColor: isDark
            ? const Color(0xFF2F241F)
            : const Color(0xFFF3F4F6),
        wallpaperColors: wallpaperColors,
        patternColor: patternColor,
        sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
        isDarkVariant: isDark,
        showDoodles: preferences.doodles,
      );
    }

    // 12. Graphite Dark Theme (mono)
    return ChatResolvedAppearance(
      accent: const Color(0xFF94A3B8),
      outgoingBubbleColors: isDark
          ? const [Color(0xFF27272A)]
          : const [Color(0xFFE2E8F0)],
      incomingBubbleColor: isDark
          ? const Color(0xFF18181B)
          : const Color(0xFFFFFFFF),
      outgoingTextColor: isDark
          ? const Color(0xFFFAFAFA)
          : const Color(0xFF0F172A),
      incomingTextColor: isDark
          ? const Color(0xFFF4F4F5)
          : const Color(0xFF18181B),
      outgoingBorderColor: isDark
          ? const Color(0xFF3F3F46)
          : const Color(0xFFCBD5E1),
      incomingBorderColor: isDark
          ? const Color(0xFF27272A)
          : const Color(0xFFE2E8F0),
      outgoingReplyColor: isDark
          ? const Color(0xFF3F3F46)
          : const Color(0xFFCBD5E1),
      incomingReplyColor: isDark
          ? const Color(0xFF27272A)
          : const Color(0xFFF1F5F9),
      wallpaperColors: wallpaperColors,
      patternColor: patternColor,
      sparkleColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.02),
      isDarkVariant: isDark,
      showDoodles: preferences.doodles,
    );
  }

  static ChatResolvedAppearance _resolveCustomAppearance({
    required ChatPreferences preferences,
    required bool isDark,
  }) {
    final custom = preferences.customTheme;
    final accent = _adaptCustomColor(
      colorFromHex(custom.accentColorHex),
      isDark: isDark,
    );
    final outgoingBubbleColors = custom.outgoingBubbleColorHexes
        .map(colorFromHex)
        .map((color) => _adaptCustomColor(color, isDark: isDark))
        .toList();
    final incomingBubbleColor = _adaptCustomIncomingColor(
      colorFromHex(custom.incomingBubbleColorHex),
      isDark: isDark,
    );
    final wallpaperColors = _wallpaperColorsFor(
      wallpaperId: preferences.wallpaperId,
      isDark: isDark,
      fallback: custom.wallpaperColorHexes
          .map(colorFromHex)
          .map((color) => _adaptCustomWallpaperColor(color, isDark: isDark))
          .toList(),
      customTheme: custom,
    );
    final patternColor = _doodleColorFor(
      wallpaperColors: wallpaperColors,
      isDark: isDark,
    );

    return ChatResolvedAppearance(
      accent: accent,
      outgoingBubbleColors: outgoingBubbleColors,
      incomingBubbleColor: incomingBubbleColor,
      outgoingTextColor: isDark
          ? Colors.white
          : (outgoingBubbleColors.isNotEmpty &&
                  outgoingBubbleColors.first.computeLuminance() < 0.45
              ? Colors.white
              : const Color(0xFF0F172A)),
      incomingTextColor: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
      outgoingBorderColor: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : accent.withValues(alpha: 0.20),
      incomingBorderColor: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06),
      outgoingReplyColor: isDark
          ? Colors.black.withValues(alpha: 0.25)
          : accent.withValues(alpha: 0.15),
      incomingReplyColor: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04),
      wallpaperColors: wallpaperColors,
      patternColor: patternColor,
      sparkleColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : accent.withValues(alpha: 0.03),
      isDarkVariant: isDark,
      showDoodles: preferences.doodles,
    );
  }

  static Color _doodleColorFor({
    required List<Color> wallpaperColors,
    required bool isDark,
  }) {
    if (isDark) {
      return Colors.white.withValues(alpha: 0.055);
    }
    final avgLuminance = wallpaperColors.isEmpty
        ? 0.9
        : wallpaperColors
                .map((c) => c.computeLuminance())
                .reduce((a, b) => a + b) /
            wallpaperColors.length;

    if (avgLuminance > 0.6) {
      return const Color(0xFF334155).withValues(alpha: 0.075);
    } else {
      return Colors.white.withValues(alpha: 0.08);
    }
  }

  static List<Color> _wallpaperColorsFor({
    required String wallpaperId,
    required bool isDark,
    required List<Color> fallback,
    required ChatCustomTheme customTheme,
  }) {
    if (wallpaperId == 'custom') {
      return customTheme.wallpaperColorHexes
          .map(colorFromHex)
          .map((color) => _adaptCustomWallpaperColor(color, isDark: isDark))
          .toList();
    }
    if (wallpaperId == 'default') {
      return fallback;
    }
    final wallpaper = wallpaperById(wallpaperId);
    return isDark ? wallpaper.darkColors : wallpaper.lightColors;
  }

  static List<Color> _defaultWallpaperForTheme(String themeId, bool isDark) {
    return switch (themeId) {
      'whatsapp' =>
        isDark
            ? const [Color(0xFF0B141A), Color(0xFF0B141A)]
            : const [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
      'telegram_night' =>
        isDark
            ? const [Color(0xFF0A1017), Color(0xFF121B24)]
            : const [Color(0xFFD9E2EC), Color(0xFFBCCCDC)],
      'telegram_arctic' =>
        isDark
            ? const [Color(0xFF0E1621), Color(0xFF17212B)]
            : const [Color(0xFFE4EDF5), Color(0xFFD6E3EF)],
      'desert_warmth' =>
        isDark
            ? const [Color(0xFF1C1712), Color(0xFF261D17)]
            : const [Color(0xFFF7F2E9), Color(0xFFEDE4D5)],
      'sage_harmony' =>
        isDark
            ? const [Color(0xFF0D1712), Color(0xFF13221A)]
            : const [Color(0xFFEBF4EE), Color(0xFFDEEDE3)],
      'classic' =>
        isDark
            ? const [Color(0xFF0E1621), Color(0xFF17212B)]
            : const [Color(0xFFE4EDF5), Color(0xFFD6E3EF)],
      'ios' =>
        isDark
            ? const [Color(0xFF141C22), Color(0xFF1B242B)]
            : const [Color(0xFFECEFF1), Color(0xFFE4E8EB)],
      'nordic_frost' =>
        isDark
            ? const [Color(0xFF141C22), Color(0xFF1B242B)]
            : const [Color(0xFFECEFF1), Color(0xFFE4E8EB)],
      'blossom_mauve' =>
        isDark
            ? const [Color(0xFF1C162E), Color(0xFF251E3C)]
            : const [Color(0xFFEDE9FE), Color(0xFFF5F2FE)],
      'mint' =>
        isDark
            ? const [Color(0xFF053E31), Color(0xFF084D3E)]
            : const [Color(0xFFD5F3E4), Color(0xFFE2F8EE)],
      'sunset' =>
        isDark
            ? const [Color(0xFF2A1B10), Color(0xFF382516)]
            : const [Color(0xFFFFEDD5), Color(0xFFFFF6EB)],
      'mono' =>
        isDark
            ? const [Color(0xFF000000), Color(0xFF080808)]
            : const [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
      _ =>
        isDark
            ? const [Color(0xFF0B141A), Color(0xFF0B141A)]
            : const [Color(0xFFEFEAE2), Color(0xFFEFEAE2)],
    };
  }

  static Color _adaptCustomColor(Color color, {required bool isDark}) {
    final luminance = color.computeLuminance();
    if (isDark) {
      final amount = luminance > 0.46 ? 0.48 : 0.28;
      return _blend(color, Colors.black, amount);
    }
    final amount = luminance < 0.18 ? 0.22 : 0.10;
    return _blend(color, Colors.white, amount);
  }

  static Color _adaptCustomIncomingColor(Color color, {required bool isDark}) {
    if (isDark) {
      return _blend(const Color(0xFF17212B), color, 0.26);
    }
    return _blend(Colors.white, color, 0.12);
  }

  static Color _adaptCustomWallpaperColor(Color color, {required bool isDark}) {
    final luminance = color.computeLuminance();
    if (isDark) {
      final amount = luminance > 0.42 ? 0.58 : 0.26;
      return _blend(color, Colors.black, amount);
    }
    final amount = luminance < 0.22 ? 0.32 : 0.08;
    return _blend(color, Colors.white, amount);
  }

  static Color _blend(Color base, Color overlay, double amount) {
    return Color.lerp(base, overlay, amount.clamp(0, 1))!;
  }

  static Color colorFromHex(String hex, {Color fallback = const Color(0xFF00A884)}) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final val = int.tryParse('FF$clean', radix: 16);
      if (val != null) return Color(val);
    } else if (clean.length == 8) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(val);
    }
    return fallback;
  }

  static String colorToHex(Color color, {bool includeAlpha = false}) {
    final a = (color.a * 255).round().toRadixString(16).padLeft(2, '0');
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return includeAlpha ? '#$a$r$g$b'.toUpperCase() : '#$r$g$b'.toUpperCase();
  }
}

class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({
    super.key,
    required this.preferences,
    required this.isDark,
  });

  final ChatPreferences preferences;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final resolved = ChatAppearanceCatalog.resolveAppearance(
      preferences: preferences,
      isDark: isDark,
      colorScheme: Theme.of(context).colorScheme,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: resolved.wallpaperColors,
          stops: _buildGradientStops(resolved.wallpaperColors.length),
        ),
      ),
      child: Stack(
        children: [
          if (preferences.doodles && resolved.showDoodles)
            Positioned.fill(
              child: CustomPaint(
                painter: WhatsAppDoodlePainter(
                  doodleColor: resolved.patternColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<double> _buildGradientStops(int length) {
    if (length <= 1) {
      return const [0];
    }
    return List<double>.generate(
      length,
      (index) => index / math.max(1, length - 1),
    );
  }
}

class WhatsAppDoodlePainter extends CustomPainter {
  const WhatsAppDoodlePainter({
    required this.doodleColor,
  });

  final Color doodleColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (doodleColor.a <= 0.005) return;

    final strokePaint = Paint()
      ..color = doodleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = doodleColor
      ..style = PaintingStyle.fill;

    const cellW = 82.0;
    const cellH = 82.0;

    final cols = (size.width / cellW).ceil() + 1;
    final rows = (size.height / cellH).ceil() + 1;

    for (int r = 0; r < rows; r++) {
      final y = r * cellH + 24;
      final xOffset = (r % 2 == 1) ? (cellW / 2) : 0.0;

      for (int c = -1; c < cols; c++) {
        final x = c * cellW + xOffset + 24;
        final iconType = ((r * 7) + c + 100) % 18;

        canvas.save();
        canvas.translate(x, y);

        switch (iconType) {
          case 0:
            _drawChatBubble(canvas, strokePaint);
            break;
          case 1:
            _drawHeart(canvas, strokePaint);
            break;
          case 2:
            _drawCoffee(canvas, strokePaint);
            break;
          case 3:
            _drawCamera(canvas, strokePaint);
            break;
          case 4:
            _drawPaperPlane(canvas, strokePaint);
            break;
          case 5:
            _drawClock(canvas, strokePaint);
            break;
          case 6:
            _drawStar(canvas, strokePaint);
            break;
          case 7:
            _drawLightbulb(canvas, strokePaint);
            break;
          case 8:
            _drawMusicNote(canvas, strokePaint, fillPaint);
            break;
          case 9:
            _drawSmiley(canvas, strokePaint, fillPaint);
            break;
          case 10:
            _drawCloud(canvas, strokePaint);
            break;
          case 11:
            _drawHeadphones(canvas, strokePaint);
            break;
          case 12:
            _drawMoon(canvas, strokePaint);
            break;
          case 13:
            _drawSparkle(canvas, strokePaint);
            break;
          case 14:
            _drawPlanet(canvas, strokePaint);
            break;
          case 15:
            _drawLeaf(canvas, strokePaint);
            break;
          case 16:
            _drawSnowflake(canvas, strokePaint);
            break;
          case 17:
            _drawPumpkin(canvas, strokePaint);
            break;
        }

        canvas.restore();
      }
    }
  }

  void _drawChatBubble(Canvas canvas, Paint paint) {
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-8, -7, 16, 12),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(rrect, paint);
    final tail = Path()
      ..moveTo(-1, 5)
      ..lineTo(-4, 9)
      ..lineTo(2, 5);
    canvas.drawPath(tail, paint);
  }

  void _drawHeart(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(0, 6)
      ..cubicTo(-7, 1, -7, -5, 0, -3)
      ..cubicTo(7, -5, 7, 1, 0, 6);
    canvas.drawPath(path, paint);
  }

  void _drawCoffee(Canvas canvas, Paint paint) {
    final cup = RRect.fromRectAndCorners(
      const Rect.fromLTWH(-6, -3, 12, 10),
      bottomLeft: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(cup, paint);
    canvas.drawLine(const Offset(-8, -3), const Offset(8, -3), paint);
    final handle = Path()
      ..moveTo(6, -1)
      ..cubicTo(9, -1, 9, 4, 6, 4);
    canvas.drawPath(handle, paint);
  }

  void _drawCamera(Canvas canvas, Paint paint) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-8, -4, 16, 11),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(body, paint);
    canvas.drawCircle(const Offset(0, 1.5), 3, paint);
    final flash = Path()
      ..moveTo(-4, -4)
      ..lineTo(-3, -7)
      ..lineTo(0, -7)
      ..lineTo(1, -4);
    canvas.drawPath(flash, paint);
  }

  void _drawPaperPlane(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-7, -7)
      ..lineTo(8, 0)
      ..lineTo(-7, 7)
      ..lineTo(-3, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawClock(Canvas canvas, Paint paint) {
    canvas.drawCircle(Offset.zero, 7, paint);
    canvas.drawLine(Offset.zero, const Offset(0, -4), paint);
    canvas.drawLine(Offset.zero, const Offset(3, 0), paint);
  }

  void _drawStar(Canvas canvas, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerX = 7 * math.cos((18 + i * 72) * math.pi / 180);
      final outerY = -7 * math.sin((18 + i * 72) * math.pi / 180);
      if (i == 0) {
        path.moveTo(outerX, outerY);
      } else {
        path.lineTo(outerX, outerY);
      }
      final innerX = 3 * math.cos((54 + i * 72) * math.pi / 180);
      final innerY = -3 * math.sin((54 + i * 72) * math.pi / 180);
      path.lineTo(innerX, innerY);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawLightbulb(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(0, -2), 5, paint);
    final base = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-3, 3, 6, 4),
      const Radius.circular(1),
    );
    canvas.drawRRect(base, paint);
  }

  void _drawMusicNote(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-3, 4), width: 5, height: 3.5),
      fill,
    );
    canvas.drawLine(const Offset(-0.5, 4), const Offset(-0.5, -6), stroke);
    final flag = Path()
      ..moveTo(-0.5, -6)
      ..quadraticBezierTo(4, -5, 4, -1);
    canvas.drawPath(flag, stroke);
  }

  void _drawSmiley(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(Offset.zero, 7, stroke);
    canvas.drawCircle(const Offset(-2.5, -2), 1, fill);
    canvas.drawCircle(const Offset(2.5, -2), 1, fill);
    final mouth = Path()
      ..moveTo(-3.5, 1.5)
      ..quadraticBezierTo(0, 4.5, 3.5, 1.5);
    canvas.drawPath(mouth, stroke);
  }

  void _drawCloud(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-6, 3)
      ..lineTo(6, 3)
      ..cubicTo(8, 3, 8, 0, 6, -1)
      ..cubicTo(6, -4, 2, -5, 0, -3)
      ..cubicTo(-2, -5, -6, -3, -5, 0)
      ..cubicTo(-8, 0, -8, 3, -6, 3);
    canvas.drawPath(path, paint);
  }

  void _drawHeadphones(Canvas canvas, Paint paint) {
    final arc = Path()
      ..addArc(
        Rect.fromCircle(center: const Offset(0, -1), radius: 6),
        math.pi,
        math.pi,
      );
    canvas.drawPath(arc, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-7, -1, 3, 6),
        const Radius.circular(1.5),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, -1, 3, 6),
        const Radius.circular(1.5),
      ),
      paint,
    );
  }

  void _drawMoon(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(4, -7)
      ..cubicTo(-3, -5, -5, 2, -1, 7)
      ..cubicTo(5, 6, 7, 2, 6, -1)
      ..cubicTo(4, 2, 0, 2, 4, -7);
    canvas.drawPath(path, paint);
  }

  void _drawSparkle(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(0, -7)
      ..quadraticBezierTo(0, 0, 7, 0)
      ..quadraticBezierTo(0, 0, 0, 7)
      ..quadraticBezierTo(0, 0, -7, 0)
      ..quadraticBezierTo(0, 0, 0, -7);
    canvas.drawPath(path, paint);
  }

  void _drawPlanet(Canvas canvas, Paint paint) {
    canvas.drawCircle(Offset.zero, 5, paint);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 16, height: 4),
      paint,
    );
  }

  void _drawLeaf(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-5, 5)
      ..quadraticBezierTo(-5, -5, 5, -5)
      ..quadraticBezierTo(5, 5, -5, 5)
      ..moveTo(-5, 5)
      ..lineTo(2, -2);
    canvas.drawPath(path, paint);
  }

  void _drawSnowflake(Canvas canvas, Paint paint) {
    for (int i = 0; i < 3; i++) {
      final angle = i * math.pi / 3;
      final dx = math.cos(angle) * 6.5;
      final dy = math.sin(angle) * 6.5;
      canvas.drawLine(Offset(-dx, -dy), Offset(dx, dy), paint);
      final bdx = math.cos(angle + math.pi / 4) * 2.2;
      final bdy = math.sin(angle + math.pi / 4) * 2.2;
      canvas.drawLine(Offset(dx * 0.65 - bdx, dy * 0.65 - bdy), Offset(dx * 0.65, dy * 0.65), paint);
      canvas.drawLine(Offset(dx * 0.65 + bdx, dy * 0.65 + bdy), Offset(dx * 0.65, dy * 0.65), paint);
    }
  }

  void _drawPumpkin(Canvas canvas, Paint paint) {
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 12, height: 9), paint);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 6, height: 9.5), paint);
    canvas.drawLine(const Offset(0, -4.5), const Offset(1.2, -7.5), paint);
  }

  @override
  bool shouldRepaint(covariant WhatsAppDoodlePainter oldDelegate) {
    return oldDelegate.doodleColor != doodleColor;
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Bubble Snow Cap Widget & Painter
// ─────────────────────────────────────────────────────────────────────────────
class BubbleSnowCap extends StatelessWidget {
  const BubbleSnowCap({
    super.key,
    required this.isMine,
    this.cornerRadius = 18.0,
  });

  final bool isMine;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -3.5,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: CustomPaint(
          size: const Size(double.infinity, 14),
          painter: _BubbleSnowCapPainter(
            isMine: isMine,
            cornerRadius: cornerRadius,
          ),
        ),
      ),
    );
  }
}

class _BubbleSnowCapPainter extends CustomPainter {
  const _BubbleSnowCapPainter({
    required this.isMine,
    required this.cornerRadius,
  });

  final bool isMine;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    if (w <= 10) return;

    final snowPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = const Color(0x3390CAF9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();
    path.moveTo(0, cornerRadius * 0.5);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    final segments = (w / 32.0).clamp(2, 8).toInt();
    final segWidth = (w - (cornerRadius * 2)) / segments;

    double currentX = cornerRadius;
    for (int i = 0; i < segments; i++) {
      final nextX = currentX + segWidth;
      final moundHeight = (i % 2 == 0) ? 4.5 : 2.5;
      path.quadraticBezierTo(
        currentX + (segWidth * 0.5),
        -moundHeight * 0.6,
        nextX,
        0,
      );
      currentX = nextX;
    }

    path.quadraticBezierTo(w, 0, w, cornerRadius * 0.5);
    path.lineTo(w - 2, 4);

    double backX = w - cornerRadius;
    for (int i = segments - 1; i >= 0; i--) {
      final prevX = backX - segWidth;
      final dipY = (i % 2 == 0) ? 5.5 : 3.0;
      path.quadraticBezierTo(
        backX - (segWidth * 0.5),
        dipY,
        prevX,
        3.0,
      );
      backX = prevX;
    }
    path.lineTo(0, 4);
    path.close();

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, snowPaint);

    final crystalPaint = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.fill;

    if (w > 60) {
      canvas.drawCircle(Offset(cornerRadius + 6, 2), 1.2, crystalPaint);
      canvas.drawCircle(Offset(w - cornerRadius - 8, 2.5), 1.0, crystalPaint);
      if (w > 120) {
        canvas.drawCircle(Offset(w * 0.5, 1.8), 1.3, crystalPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BubbleSnowCapPainter oldDelegate) =>
      oldDelegate.isMine != isMine || oldDelegate.cornerRadius != cornerRadius;
}
