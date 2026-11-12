import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مخزن محلي لحفظ واسترجاع أحدث التفاعلات المستخدمة بأسلوب WhatsApp
class WhatsAppReactionHistory {
  WhatsAppReactionHistory._();
  static const _key = 'whatsapp_recent_reactions_list_v1';

  static const List<String> defaultRecents = [
    '❤️', '👍', '😂', '🔥', '👏', '😮', '😍', '😭',
    '🙏', '🎉', '👌', '💯', '🤔', '🥰', '✨', '💪',
    '🥳', '😎', '💔', '🤝', '🙌', '😢', '👀', '✅',
  ];

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key);
      if (list != null && list.isNotEmpty) {
        return list;
      }
    } catch (_) {}
    return defaultRecents;
  }

  static Future<void> add(String emoji) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_key) ?? List<String>.from(defaultRecents);
      current.remove(emoji);
      current.insert(0, emoji);
      if (current.length > 28) {
        current.removeRange(28, current.length);
      }
      await prefs.setStringList(_key, current);
    } catch (_) {}
  }
}

class _EmojiCategory {
  final String id;
  final String title;
  final String icon;
  final List<String> emojis;

  const _EmojiCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.emojis,
  });
}

/// ورقة اختيار التفاعلات بأسلوب WhatsApp iOS الأصلي
class WhatsAppReactionPickerSheet extends StatefulWidget {
  const WhatsAppReactionPickerSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => const WhatsAppReactionPickerSheet(),
    );
  }

  @override
  State<WhatsAppReactionPickerSheet> createState() =>
      _WhatsAppReactionPickerSheetState();
}

class _WhatsAppReactionPickerSheetState
    extends State<WhatsAppReactionPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<String> _recentEmojis = [];
  String _selectedCategoryId = 'recent';
  String _searchQuery = '';

  static const List<_EmojiCategory> _categories = [
    _EmojiCategory(
      id: 'smileys',
      title: 'الوجوه والتعبيرات',
      icon: '😀',
      emojis: [
        '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🥲', '🥹',
        '☺️', '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘',
        '😗', '😙', '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐',
        '🤓', '😎', '🥸', '🤩', '🥳', '😏', '😒', '😞', '😔', '😟',
        '😕', '🙁', '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😮‍💨',
        '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨',
        '😰', '😥', '😓', '🫣', '🤗', '🫡', '🤔', '🫢', '🤫', '🤥',
        '😶', '😐', '😑', '😬', '🫨', '🫠', '🙄', '😯', '😦', '😧',
        '😮', '😲', '🥱', '😴', '🤤', '😪', '😵', '😵‍💫', '🤐', '🥴',
        '🤢', '🤮', '🤧', '😷', '🤒', '🤕', '🤑', '🤠', '😈', '👿',
        '👹', '👺', '🤡', '💩', '👻', '💀', '☠️', '👽', '👾', '🤖',
        '🎃', '😺', '😸', '😹', '😻', '😼', '😽', '🙀', '😿', '😾',
      ],
    ),
    _EmojiCategory(
      id: 'gestures',
      title: 'الإيماءات والأشخاص',
      icon: '🖐️',
      emojis: [
        '👋', '🤚', '🖐️', '✋', '🖖', '🫱', '🫲', '🫳', '🫴', '🫷',
        '🫸', '👌', '🤌', '🤏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙',
        '👈', '👉', '👆', '🖕', '👇', '☝️', '🫵', '👍', '👎', '✊',
        '👊', '🤛', '🤜', '👏', '🙌', '🫶', '👐', '🤲', '🤝', '🙏',
        '✍️', '💅', '🤳', '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻',
        '👃', '🧠', '🫀', '🫁', '🦷', '🦴', '👀', '👁️', '👅', '👄',
        '🫦', '👶', '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔', '👩',
        '🧓', '👴', '👵', '👮', '👷', '💂', '🕵️', '🧑‍⚕️', '🧑‍🌾', '🧑‍🍳',
        '🧑‍🎓', '🧑‍🎤', '🧑‍🏫', '🧑‍🏭', '🧑‍💻', '🧑‍💼', '🧑‍🔧', '🧑‍🔬', '🧑‍🎨', '🧑‍🚒',
        '🧑‍✈️', '🧑‍🚀', '🧑‍⚖️', '👰', '🤵', '🦸', '🦹', '🧙', '🧚', '🧛',
        '🧜', '🧝', '🧞', '🧟', '💃', '🕺', '🧗', '🤺', '🏇', '🏄',
      ],
    ),
    _EmojiCategory(
      id: 'animals',
      title: 'الحيوانات والطبيعة',
      icon: '🐶',
      emojis: [
        '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐻‍❄️', '🐨',
        '🐯', '🦁', '🐮', '🐷', '🐽', '🐸', '🐵', '🙈', '🙉', '🙊',
        '🐒', '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉',
        '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪱', '🐛', '🦋', '🐌',
        '🐞', '🐜', '🪰', '🪲', '🪳', '🦟', '🦗', '🕷️', '🕸️', '🦂',
        '🐢', '🐍', '🦎', '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀',
        '🐡', '🐠', '🐟', '🐬', '🐳', '🐋', '🦈', '🐊', '🐆', '🐅',
        '🐃', '🐂', '🐄', '🦌', '🐪', '🐫', '🦙', '🦒', '🐘', '🦣',
        '🦏', '🦛', '🐁', '🐀', '🐿️', '🦫', '🦔', '🌲', '🌳', '🌴',
        '🌵', '🌾', '🌿', '☘️', '🍀', '🍁', '🍂', '🍃', '🪴', '🍄',
        '🪸', '💐', '🌸', '💮', '🪷', '🏵️', '🌹', '🥀', '🌺', '🌻',
        '🌼', '🌷', '🪻', '🌱', '🌍', '🪐', '💫', '⭐', '🌟', '✨',
        '⚡', '💥', '🔥', '🌪️', '🌈', '☀️', '🌤️', '⛅', '🌧️', '❄️',
      ],
    ),
    _EmojiCategory(
      id: 'food',
      title: 'الأطعمة والمشروبات',
      icon: '🍔',
      emojis: [
        '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
        '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑',
        '🥦', '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅',
        '🥔', '🍠', '🥐', '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳',
        '🧈', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🌭', '🍔', '🍟',
        '🍕', '🫓', '🥪', '🥙', '🧆', '🌮', '🌯', '🫔', '🥗', '🥘',
        '🫕', '🥫', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🍤',
        '🍙', '🍚', '🍘', '🍥', '🥠', '🥮', '🍢', '🍡', '🍧', '🍨',
        '🍦', '🥧', '🧁', '🍰', '🎂', '🍮', '🍭', '🍬', '🍫', '🍿',
        '🍩', '🍪', '🌰', '🥜', '🍯', '🥛', '🍼', '🫖', '☕', '🍵',
        '🧃', '🥤', '🧋', '🍶', '🍺', '🍻', '🥂', '🍷', '🥃', '🍸',
      ],
    ),
    _EmojiCategory(
      id: 'activities',
      title: 'الأنشطة والرياضة',
      icon: '⚽',
      emojis: [
        '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
        '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳',
        '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷',
        '⛸️', '🎿', '⛷️', '🏂', '🪂', '🏋️', '🤼', '🤸', '⛹️', '🤺',
        '🤾', '🏌️', '🏇', '🧘', '🏄', '🏊', '🤽', '🚣', '🧗', '🚴',
        '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🏵️', '🎗️', '🎫', '🎟️',
        '🎪', '🤹', '🎭', '🩰', '🎨', '🎬', '🎤', '🎧', '🎼', '🎹',
        '🥁', '🪘', '🎷', '🎺', '🪗', '🎸', '🪕', '🎻', '🎲', '♟️',
        '🎯', '🎳', '🎮', '🎰', '🧩',
      ],
    ),
    _EmojiCategory(
      id: 'travel',
      title: 'السفر والأماكن',
      icon: '🚗',
      emojis: [
        '🚗', '🚙', '🚕', '🛺', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒',
        '🚐', '🛻', '🚚', '🚛', '🚜', '🛴', '🚲', '🛵', '🏍️', '🚨',
        '🚔', '🚍', '🚘', '🚖', '🚡', '🚠', '🚟', '🚃', '🚋', '🚂',
        '🚆', '🚇', '🚊', '🚉', '✈️', '🛫', '🛬', '🛩️', '💺', '🛰️',
        '🚀', '🛸', '🚁', '🛶', '⛵', '🚤', '🛳️', '⛴️', '🚢', '⚓',
        '🛟', '⛽', '🚧', '🛑', '🚥', '🚦', '🚏', '🗺️', '🗿', '🗽',
        '🗼', '🏰', '🏯', '🏟️', '🎡', '🎢', '🎠', '⛲', '⛱️', '🏖️',
        '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🗻', '⛺', '🏠', '🏡', '🏢',
      ],
    ),
    _EmojiCategory(
      id: 'objects',
      title: 'الأشياء والأدوات',
      icon: '💡',
      emojis: [
        '⌚', '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🕹️', '💽',
        '💾', '💿', '📀', '📷', '📸', '📹', '🎥', '📽️', '📞', '☎️',
        '📟', '📠', '📺', '📻', '🎙️', '🧭', '⏱️', '⏲️', '⏰', '🕰️',
        '⌛', '⏳', '📡', '🔋', '🪫', '🔌', '💡', '🔦', '🕯️', '🧯',
        '💸', '💵', '💴', '💶', '💷', '🪙', '💰', '💳', '💎', '⚖️',
        '🪜', '🧰', '🪛', '🔧', '🔨', '🛠️', '⛏️', '🪚', '🔩', '⚙️',
        '🧱', '⛓️', '🧲', '🔫', '💣', '🧨', '🪓', '🔪', '🗡️', '⚔️',
        '🛡️', '⚰️', '🏺', '🔮', '📿', '🧿', '🪬', '💈', '⚗️', '🔭',
        '🔬', '🩹', '🩺', '💊', '💉', '🩸', '📦', '✉️', '📩', '📨',
        '📧', '💌', '📝', '📁', '📂', '📄', '📊', '📈', '🔒', '🔑',
      ],
    ),
    _EmojiCategory(
      id: 'symbols',
      title: 'الرموز والقلوب',
      icon: '💖',
      emojis: [
        '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
        '❤️‍🔥', '❤️‍🩹', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟',
        '☮️', '✝️', '☪️', '🕉️', '☸️', '✡️', '🔯', '🕎', '☯️', '☦️',
        '🛐', '⛎', '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏',
        '♐', '♑', '♒', '♓', '🆔', '⚛️', '☢️', '☣️', '📴', '📳',
        '🈶', '🈚', '🈸', '🈺', '🈷️', '✴️', '🆚', '💮', '🉐', '㊙️',
        '㊗️', '🈴', '🈵', '🈹', '🈲', '🅰️', '🅱️', '🆎', '🆑', '🅾️',
        '🆘', '❌', '⭕', '🛑', '⛔', '📛', '🚫', '💯', '💢', '♨️',
        '🚷', '🚯', '🚳', '🚱', '🔞', '📵', '🚭', '❗', '❕', '❓',
        '❔', '‼️', '⁉️', '🔅', '🔆', '⚠️', '🚸', '🔱', '🔰', '♻️',
        '✅', '🈯', '💹', '❇️', '✳️', '❎', '🌐', '💠', '🌀', '💤',
        '🔟', '🔢', '#️⃣', '*️⃣', '0️⃣', '1️⃣', '2️⃣', '3️⃣', '4️⃣',
        '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔴', '🟠', '🟡', '🟢', '🔵',
        '🟣', '⚫', '⚪', '🟤', '🔺', '🔻', '🔶', '🔷', '⬛', '⬜',
      ],
    ),
  ];

  static const Map<String, List<String>> _searchKeywords = {
    'حب': ['❤️', '😍', '🥰', '😘', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '🫶', '😻', '💌'],
    'قلب': ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❤️‍🔥', '❤️‍🩹', '💕', '💞', '💓', '💗', '💖'],
    'ضحك': ['😂', '🤣', '😆', '😄', '😁', '😹', '😃'],
    'فرح': ['😀', '😃', '😄', '😁', '😆', '🥳', '🎉', '🎊', '✨'],
    'ابتسامة': ['😊', '🙂', '😇', '😌', '😉'],
    'غمزة': ['😉', '😜', '😝'],
    'بكى': ['😭', '😢', '🥺', '😿', '😥', '😓'],
    'دموع': ['😭', '😢', '🥺', '😿', '💧'],
    'حزن': ['😢', '😭', '😞', '😔', '😟', '🙁', '☹️', '🥺', '😿'],
    'نار': ['🔥', '💥', '🧨', '♨️'],
    'تصفيق': ['👏', '🙌'],
    'دعاء': ['🙏', '🤲'],
    'شكر': ['🙏', '🤝', '💐'],
    'تحية': ['👋', '🫡', '🤝'],
    'قوة': ['💪', '🦾', '🏋️'],
    'تمام': ['👍', '👌', '✅', '✔️', '💯'],
    'لايك': ['👍'],
    'ديسلايك': ['👎'],
    'عين': ['👀', '👁️'],
    'بوسة': ['😘', '😗', '😙', '😚', '💋'],
    'قبلة': ['😘', '😗', '😙', '😚', '💋'],
    'صدمة': ['😮', '😲', '😱', '🤯', '😳', '🫢'],
    'تفكير': ['🤔', '🧐'],
    'نوم': ['😴', '🥱', '💤', '😪'],
    'غضب': ['😠', '😡', '🤬', '😤', '👿'],
    'شيطان': ['😈', '👿'],
    'ورد': ['🌹', '🌸', '💐', '🌺', '🌻', '🌼', '🌷'],
    'قهوة': ['☕', '🧋', '🍵'],
    'شاي': ['🍵', '🫖', '☕'],
    'سيارة': ['🚗', '🚙', '🏎️', '🚕', '🚓'],
    'طائرة': ['✈️', '🛫', '🛬', '🚀'],
    'كرة': ['⚽', '🏀', '🏈', '⚾', '🎾', '🏐'],
    'احتفال': ['🥳', '🎉', '🎊', '🍾', '🥂', '🎂'],
    'نجمة': ['⭐', '🌟', '✨', '💫'],
    'تاج': ['👑'],
    'فلوس': ['💰', '💵', '💸', '🤑'],
    'موسيقى': ['🎵', '🎶', '🎧', '🎸', '🎹', '🎤'],
    'صح': ['✅', '✔️', '💯'],
    'غلط': ['❌', '❎'],
    'مطر': ['🌧️', '🌦️', '⛈️', '☔'],
    'ثلج': ['❄️', '⛄', '☃️'],
    'ساعة': ['⏰', '⏱️', '⌚', '⏳'],
    'قفل': ['🔒', '🔓', '🔐'],
    'love': ['❤️', '😍', '🥰', '😘', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '🫶'],
    'heart': ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❤️‍🔥', '❤️‍🩹', '💕', '💞', '💓', '💗', '💖'],
    'laugh': ['😂', '🤣', '😆', '😄', '😁'],
    'smile': ['😀', '😃', '😄', '😁', '😊', '🙂'],
    'cry': ['😭', '😢', '🥺', '😥', '😓'],
    'sad': ['😢', '😭', '😞', '😔', '😟', '🙁'],
    'fire': ['🔥', '💥'],
    'clap': ['👏', '🙌'],
    'pray': ['🙏', '🤲'],
    'ok': ['👌', '👍', '✅'],
    'yes': ['👍', '✅', '✔️'],
    'no': ['👎', '❌'],
    'think': ['🤔', '🧐'],
    'sleep': ['😴', '🥱', '💤'],
    'party': ['🥳', '🎉', '🎊', '🍾'],
    'cool': ['😎'],
    'angry': ['😠', '😡', '🤬'],
    'shock': ['😮', '😲', '😱', '🤯'],
    'star': ['⭐', '🌟', '✨', '💫'],
    'coffee': ['☕', '🧋'],
    'car': ['🚗', '🚙', '🏎️'],
    'money': ['💰', '💵', '💸', '🤑'],
  };

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadRecents() async {
    final list = await WhatsAppReactionHistory.load();
    if (mounted) {
      setState(() {
        _recentEmojis = list;
      });
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onEmojiTapped(String emoji) {
    HapticFeedback.lightImpact();
    WhatsAppReactionHistory.add(emoji);
    Navigator.of(context).pop(emoji);
  }

  List<String> _getSearchResults(String query) {
    if (query.isEmpty) return const [];
    final lower = query.toLowerCase();
    final results = <String>{};

    for (final entry in _searchKeywords.entries) {
      if (entry.key.contains(lower) || lower.contains(entry.key)) {
        results.addAll(entry.value);
      }
    }

    for (final cat in _categories) {
      if (cat.title.toLowerCase().contains(lower)) {
        results.addAll(cat.emojis);
      }
      for (final em in cat.emojis) {
        if (em == query) {
          results.add(em);
        }
      }
    }

    return results.toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final sheetHeight = size.height * 0.62;

    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final searchBgColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF2F2F7);

    final isSearching = _searchQuery.isNotEmpty;
    final searchResults = isSearching ? _getSearchResults(_searchQuery) : const <String>[];

    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: TextStyle(
          decoration: TextDecoration.none,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          color: isDark ? Colors.white : Colors.black87,
        ),
        child: Container(
          height: sheetHeight,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Grab handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Search bar (WhatsApp / iOS style)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: searchBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Icon(
                        CupertinoIcons.search,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: isDark ? Colors.white : Colors.black87,
                            decoration: TextDecoration.none,
                          ),
                          decoration: InputDecoration(
                            hintText: 'ابحث عن رمز تعبيري...',
                            hintStyle: TextStyle(
                              fontSize: 14.5,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              CupertinoIcons.clear_circled_solid,
                              size: 17,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Category icons horizontal navigation bar (WhatsApp style)
              if (!isSearching)
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (_recentEmojis.isNotEmpty)
                        _buildCategoryTab(
                          id: 'recent',
                          label: '🕒',
                          tooltip: 'مؤخراً',
                          isSelected: _selectedCategoryId == 'recent',
                          isDark: isDark,
                        ),
                      for (final cat in _categories)
                        _buildCategoryTab(
                          id: cat.id,
                          label: cat.icon,
                          tooltip: cat.title,
                          isSelected: _selectedCategoryId == cat.id,
                          isDark: isDark,
                        ),
                    ],
                  ),
                ),

              Divider(
                height: 1,
                thickness: 0.5,
                color: isDark ? Colors.white12 : Colors.black12,
              ),

              // Main content: either search results, or selected category emojis
              Expanded(
                child: isSearching
                    ? (searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.search,
                                  size: 40,
                                  color: isDark ? Colors.white24 : Colors.black26,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'لا توجد نتائج مطابقة',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _buildEmojiGrid(searchResults))
                    : _buildCategoryView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTab({
    required String id,
    required String label,
    required String tooltip,
    required bool isSelected,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedCategoryId = id;
        });
      },
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? const Color(0xFF007AFF).withValues(alpha: 0.28)
                    : const Color(0xFF007AFF).withValues(alpha: 0.12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.5),
                    width: 1,
                  )
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                decoration: TextDecoration.none,
                color: isSelected ? const Color(0xFF007AFF) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryView() {
    List<String> emojis;
    String title;

    if (_selectedCategoryId == 'recent') {
      emojis = _recentEmojis;
      title = 'الأحدث استخداماً';
    } else {
      final category = _categories.firstWhere(
        (c) => c.id == _selectedCategoryId,
        orElse: () => _categories.first,
      );
      emojis = category.emojis;
      title = category.title;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black54,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final emoji = emojis[index];
                return _buildEmojiButton(emoji);
              },
              childCount: emojis.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 24),
        ),
      ],
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return _buildEmojiButton(emoji);
      },
    );
  }

  Widget _buildEmojiButton(String emoji) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onEmojiTapped(emoji),
        borderRadius: BorderRadius.circular(12),
        splashColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
        highlightColor: const Color(0xFF007AFF).withValues(alpha: 0.08),
        child: Center(
          child: Text(
            emoji,
            style: const TextStyle(
              fontSize: 27,
              height: 1.1,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
