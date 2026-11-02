import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;

class IslandSettingsView extends ConsumerStatefulWidget {
  const IslandSettingsView({super.key, required this.isDark});

  final bool isDark;

  @override
  ConsumerState<IslandSettingsView> createState() => _IslandSettingsViewState();
}

class _IslandSettingsViewState extends ConsumerState<IslandSettingsView> {
  bool _isLoading = true;
  bool _enabled = true;
  String _privacyMode = 'full'; // 'full', 'sender_only', 'hidden'
  String _theme = 'obsidian'; // 'obsidian', 'midnight', 'neon', 'emerald', 'crimson'
  bool _soundEnabled = true;
  bool _startMinimizedOnBoot = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await web_bridge.islandGetSettings();
      if (settings != null && mounted) {
        setState(() {
          _enabled = settings['enabled'] != false;
          _privacyMode = (settings['privacyMode'] as String?) ?? 'full';
          _theme = (settings['theme'] as String?) ?? 'obsidian';
          _soundEnabled = settings['soundEnabled'] != false;
          _startMinimizedOnBoot = settings['startMinimizedOnBoot'] != false;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings({
    bool? enabled,
    String? privacyMode,
    String? theme,
    bool? soundEnabled,
    bool? startMinimizedOnBoot,
  }) async {
    final nextEnabled = enabled ?? _enabled;
    final nextPrivacy = privacyMode ?? _privacyMode;
    final nextTheme = theme ?? _theme;
    final nextSound = soundEnabled ?? _soundEnabled;
    final nextBoot = startMinimizedOnBoot ?? _startMinimizedOnBoot;

    setState(() {
      _enabled = nextEnabled;
      _privacyMode = nextPrivacy;
      _theme = nextTheme;
      _soundEnabled = nextSound;
      _startMinimizedOnBoot = nextBoot;
      _isSaving = true;
    });

    try {
      await web_bridge.islandSaveSettings({
        'enabled': nextEnabled,
        'privacyMode': nextPrivacy,
        'theme': nextTheme,
        'soundEnabled': nextSound,
        'startMinimizedOnBoot': nextBoot,
      });
    } catch (_) {}

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _triggerTestNotification() async {
    await web_bridge.islandTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إرسال إشعار تجريبي إلى الجزيرة التفاعلية 🔔'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _triggerTestWelcome() async {
    final user = ref.read(currentUserProvider);
    await web_bridge.islandTriggerWelcome({
      'userName': user?.fullName.isNotEmpty == true ? user?.fullName : user?.username,
      'avatarUrl': user?.avatarUrl,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم عرض شاشة الترحيب في الجزيرة التفاعلية ✨'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _triggerTestProgress() async {
    await web_bridge.islandTriggerProgress({
      'label': 'جاري نقل الملف: Document_Scan_2026.pdf',
      'percent': 68,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إرسال حالة شريط التقدم إلى الجزيرة التفاعلية 📊'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Hero Showcase Card
        _buildHeroBanner(isDark),
        const SizedBox(height: 20),

        // 2. Master Toggle & Core Preferences
        _buildMasterGroup(isDark),
        const SizedBox(height: 20),

        // 3. Theme Engine Picker
        _buildThemeSelector(isDark),
        const SizedBox(height: 20),

        // 4. Privacy & Notifications
        _buildPrivacyAndSoundGroup(isDark),
        const SizedBox(height: 20),

        // 5. Interactive Testing Lab
        _buildTestingLab(isDark),
      ],
    );
  }

  Widget _buildHeroBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0F172A), const Color(0xFF020617)]
              : [const Color(0xFFE0F2FE), const Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.view_stream_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'الجزيرة التفاعلية (Dynamic Island)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _enabled
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _enabled ? 'نشطة الآن ✓' : 'معطلة',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _enabled ? const Color(0xFF10B981) : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'شريط تفاعلي عائم ودائم أعلى شاشة الويندوز فوق كل البرامج، حتى لو قمت بتصغير التطبيق أو إغلاقه إلى شريط المهام (Tray). يعرض الرسائل فوراً مع رد سريع بدون فتح التطبيق.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterGroup(bool isDark) {
    return _buildInsetCard(
      isDark: isDark,
      title: 'التحكم العام بالجزيرة والتشغيل',
      children: [
        SwitchListTile.adaptive(
          value: _enabled,
          onChanged: (val) => _saveSettings(enabled: val),
          title: const Text(
            'تفعيل شريط الجزيرة التفاعلية على الويندوز',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: const Text(
            'ظهور الكبسولة التفاعلية دائماً في أعلى منتصف الشاشة وتفاعلها مع النظام والرسائل.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const Divider(height: 0.5, indent: 16),
        SwitchListTile.adaptive(
          value: _startMinimizedOnBoot,
          onChanged: _enabled
              ? (val) => _saveSettings(startMinimizedOnBoot: val)
              : null,
          title: const Text(
            'بدء التشغيل في الخلفية مع الويندوز (Background Launch)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: const Text(
            'عند إقلاع الجهاز، تظهر الجزيرة التفاعلية مع ترحيب البدء بينما يبقى التطبيق في الخلفية بهدوء.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeSelector(bool isDark) {
    final themes = [
      (
        id: 'obsidian',
        name: 'أسود أوبسيديان',
        desc: 'أناقة داكنة فخمة (Nova / iOS)',
        color: const Color(0xFF0A0C12),
        accent: const Color(0xFF3B82F6),
      ),
      (
        id: 'midnight',
        name: 'أزرق ليلي',
        desc: 'أجواء الفضاء الكحلي الهادئ',
        color: const Color(0xFF071124),
        accent: const Color(0xFF38BDF8),
      ),
      (
        id: 'neon',
        name: 'نيون سايبر',
        desc: 'توهج بنفسجي مستقبلي مميز',
        color: const Color(0xFF0F0A1C),
        accent: const Color(0xFFC084FC),
      ),
      (
        id: 'emerald',
        name: 'أخضر زمردي',
        desc: 'ألوان حيوية مريحة وراقية',
        color: const Color(0xFF04140E),
        accent: const Color(0xFF10B981),
      ),
      (
        id: 'crimson',
        name: 'أحمر قرمزي',
        desc: 'طابع دافئ وجريء',
        color: const Color(0xFF18060A),
        accent: const Color(0xFFF43F5E),
      ),
    ];

    return _buildInsetCard(
      isDark: isDark,
      title: 'مظهر وألوان الجزيرة التفاعلية (Themes)',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: themes.map((t) {
                  final isSelected = _theme == t.id;
                  return SizedBox(
                    width: (constraints.maxWidth - 24) / 2 > 240
                        ? (constraints.maxWidth - 24) / 3
                        : (constraints.maxWidth - 12) / 2,
                    child: InkWell(
                      onTap: _enabled ? () => _saveSettings(theme: t.id) : null,
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? (isSelected
                                  ? t.accent.withValues(alpha: 0.18)
                                  : const Color(0xFF232326))
                              : (isSelected
                                  ? t.accent.withValues(alpha: 0.1)
                                  : const Color(0xFFF7F7FA)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? t.accent
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06)),
                            width: isSelected ? 2.0 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: t.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: t.accent, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: t.accent.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                      fontSize: 13,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    t.desc,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyAndSoundGroup(bool isDark) {
    return _buildInsetCard(
      isDark: isDark,
      title: 'الخصوصية والأصوات التفاعلية',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: DropdownButtonFormField<String>(
            value: _privacyMode,
            decoration: const InputDecoration(
              labelText: 'مستوى خصوصية عرض الرسائل في الجزيرة',
              prefixIcon: Icon(Icons.security_rounded, size: 20),
              border: InputBorder.none,
            ),
            items: const [
              DropdownMenuItem(
                value: 'full',
                child: Text('عرض كامل (اسم الراسل + نص الرسالة + الصورة)'),
              ),
              DropdownMenuItem(
                value: 'sender_only',
                child: Text('عرض اسم الراسل فقط مع إخفاء نص الرسالة'),
              ),
              DropdownMenuItem(
                value: 'hidden',
                child: Text('خصوصية كاملة (إخفاء المحتوى واسم الراسل)'),
              ),
            ],
            onChanged: _enabled ? (val) => _saveSettings(privacyMode: val) : null,
          ),
        ),
        const Divider(height: 0.5, indent: 16),
        SwitchListTile.adaptive(
          value: _soundEnabled,
          onChanged: _enabled ? (val) => _saveSettings(soundEnabled: val) : null,
          title: const Text(
            'نغمات التنبيه التفاعلية (Harmonic Audio Chimes)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: const Text(
            'نغمات سنثيزر جرس عالية النقاء والنقاء تعمل عبر Web Audio API بدون أي ملفات صوتية خارجية.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTestingLab(bool isDark) {
    return _buildInsetCard(
      isDark: isDark,
      title: 'مختبر التجربة الفورية (Live Preview & Test)',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'يمكنك تجربة جميع حالات وحركات الجزيرة التفاعلية مباشرة والتأكد من انسيابيتها على شاشتك:',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _enabled ? _triggerTestNotification : null,
                    icon: const Icon(Icons.notifications_active_rounded, size: 17),
                    label: const Text('تجربة إشعار وارد + رد سريع'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _enabled ? _triggerTestWelcome : null,
                    icon: const Icon(Icons.waving_hand_rounded, size: 17),
                    label: const Text('تجربة ترحيب البدء'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _enabled ? _triggerTestProgress : null,
                    icon: const Icon(Icons.sync_rounded, size: 17),
                    label: const Text('تجربة شريط النقل'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsetCard({
    required bool isDark,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: isDark ? const Color(0xFF98989D) : const Color(0xFF6C6C70),
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              width: 0.8,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
