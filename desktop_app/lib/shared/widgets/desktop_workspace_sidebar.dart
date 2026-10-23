import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../providers/providers.dart';
import 'safe_network_avatar.dart';
import 'server_settings_dialog.dart';
import '../../features/chat/presentation/chat_realtime_controller.dart';

enum DesktopWorkspaceSection {
  chat,
  files,
  workspace,
  profile,
  admin,
  printers,
  purchaseRequests,
  servers,
  tickets,
  snipeit,
  systemMonitor,
}

class DesktopWorkspaceSidebar extends ConsumerWidget {
  const DesktopWorkspaceSidebar({
    super.key,
    required this.user,
    required this.activeSection,
    required this.currentThemeMode,
    required this.isDark,
    required this.accentColor,
    required this.onOpenChat,
    required this.onRefresh,
    required this.onOpenFiles,
    this.onOpenWorkspace,
    required this.onOpenServers,
    this.showServersShortcut = true,
    required this.onOpenProfile,
    this.onOpenUpdates,
    this.hasPulsingUpdate = false,
    required this.onToggleTheme,
    required this.onOpenTickets,
    this.onOpenPrinters,
    required this.onLogout,
    this.onCreateConversation,
    this.onOpenAdmin,
    this.onOpenSystemMonitor,
    this.onOpenPurchaseRequests,
    this.onOpenSnipeit,
  });

  final AppUser? user;
  final DesktopWorkspaceSection activeSection;
  final ThemeMode currentThemeMode;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onOpenChat;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFiles;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback onOpenServers;
  final bool showServersShortcut;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenUpdates;
  final bool hasPulsingUpdate;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenTickets;
  final VoidCallback? onOpenPrinters;
  final VoidCallback onLogout;
  final VoidCallback? onCreateConversation;
  final VoidCallback? onOpenAdmin;
  final VoidCallback? onOpenSystemMonitor;
  final VoidCallback? onOpenPurchaseRequests;
  final VoidCallback? onOpenSnipeit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatOverviewControllerProvider);
    final unreadCount = chatState.valueOrNull?.totalUnread ?? 0;
    final agent = ref.watch(desktopUpdateAgentProvider);

    final ticketsState = ref.watch(ticketsControllerProvider);
    final ticketsOverview = ticketsState.valueOrNull;
    final pendingTicketsCount = ticketsOverview != null
        ? ticketsOverview.tickets.where((ticket) {
            final isNotClosed = ticket.status != 'closed' && ticket.status != 'resolved';
            final isOpen = ticket.status == 'open';
            final hasNoReply = ticket.lastPublicMessage.trim().isEmpty;
            return isOpen || (isNotClosed && hasNoReply && ticket.assignedTo == null);
          }).length
        : 0;

    return ListenableBuilder(
      listenable: Listenable.merge([
        agent.hasPreparedUpdateNotifier,
        agent.hasUpdateAvailableNotifier,
      ]),
      builder: (context, _) {
        final hasPrepared = agent.hasPreparedUpdateNotifier.value;
        final hasAvailable = agent.hasUpdateAvailableNotifier.value;
        final showPulsing = hasPrepared || hasAvailable || hasPulsingUpdate;

    final displayName = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim()
        : (user?.username ?? 'المستخدم');

    // 1. Main navigation items
    final mainActions = <Widget>[
      _DesktopWorkspaceIconButton(
        tooltip: 'المحادثات',
        icon: CupertinoIcons.chat_bubble_2,
        selectedIcon: CupertinoIcons.chat_bubble_2_fill,
        selected: activeSection == DesktopWorkspaceSection.chat,
        isDark: isDark,
        accentColor: accentColor,
        badgeCount: unreadCount,
        onPressed: onOpenChat,
      ),
      _DesktopWorkspaceIconButton(
        tooltip: 'الملفات',
        icon: CupertinoIcons.folder,
        selectedIcon: CupertinoIcons.folder_fill,
        selected: activeSection == DesktopWorkspaceSection.files,
        isDark: isDark,
        accentColor: accentColor,
        onPressed: onOpenFiles,
      ),
      _DesktopWorkspaceIconButton(
        tooltip: 'مساحة العمل والملاحظات',
        icon: CupertinoIcons.doc_text,
        selectedIcon: CupertinoIcons.doc_text_fill,
        selected: activeSection == DesktopWorkspaceSection.workspace,
        isDark: isDark,
        accentColor: accentColor,
        onPressed: onOpenWorkspace ??
            () {
              ref.read(activeSectionProvider.notifier).state =
                  DesktopWorkspaceSection.workspace;
              ref.read(chatSectionVisibleProvider.notifier).state = false;
            },
      ),
      if (showServersShortcut)
        _DesktopWorkspaceIconButton(
          tooltip: 'السيرفرات والخدمات',
          icon: CupertinoIcons.cloud,
          selectedIcon: CupertinoIcons.cloud_fill,
          selected: activeSection == DesktopWorkspaceSection.servers,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenServers,
        ),
    ];

    // 2. Operational & Admin items (when enabled/available)
    final opsActions = <Widget>[
      _DesktopWorkspaceIconButton(
        tooltip: 'تذاكر الدعم',
        icon: CupertinoIcons.tickets,
        selectedIcon: CupertinoIcons.tickets_fill,
        selected: activeSection == DesktopWorkspaceSection.tickets,
        isDark: isDark,
        accentColor: accentColor,
        badgeCount: pendingTicketsCount,
        onPressed: onOpenTickets,
      ),
      if (onOpenSystemMonitor != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'مراقبة النظام',
          icon: CupertinoIcons.speedometer,
          selectedIcon: CupertinoIcons.speedometer,
          selected: activeSection == DesktopWorkspaceSection.systemMonitor,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenSystemMonitor!,
        ),
      if (onOpenAdmin != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'لوحة الإدارة',
          icon: CupertinoIcons.shield,
          selectedIcon: CupertinoIcons.shield_fill,
          selected: activeSection == DesktopWorkspaceSection.admin,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenAdmin!,
        ),
      if (onOpenPrinters != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'إدارة الطابعات',
          icon: CupertinoIcons.printer,
          selectedIcon: CupertinoIcons.printer_fill,
          selected: activeSection == DesktopWorkspaceSection.printers,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenPrinters!,
        ),
      if (onOpenSnipeit != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'Snipe-IT',
          icon: CupertinoIcons.desktopcomputer,
          selectedIcon: CupertinoIcons.desktopcomputer,
          selected: activeSection == DesktopWorkspaceSection.snipeit,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenSnipeit!,
        ),
    ];

    // 3. System & user utility items at the bottom
    final bottomActions = <Widget>[
      if (onOpenUpdates != null)
        _DesktopWorkspaceIconButton(
          tooltip: hasPrepared
              ? 'تحديث جاهز للتثبيت (اضغط لإعادة التشغيل)'
              : hasAvailable
              ? 'يوجد تحديث جديد متاح للمنظومة'
              : 'التحديثات',
          icon: CupertinoIcons.arrow_down_circle,
          selectedIcon: CupertinoIcons.arrow_down_circle_fill,
          isDark: isDark,
          accentColor: accentColor,
          hasPulsingBadge: showPulsing,
          onPressed: onOpenUpdates!,
        ),
      _DesktopWorkspaceIconButton(
        tooltip: isDark
            ? 'التبديل إلى الوضع الفاتح'
            : 'التبديل إلى الوضع الداكن',
        icon: isDark
            ? CupertinoIcons.moon_stars_fill
            : CupertinoIcons.sun_max_fill,
        isDark: isDark,
        accentColor: accentColor,
        customIconColor: isDark
            ? const Color(0xFFFBBF24)
            : const Color(0xFFF59E0B),
        onPressed: onToggleTheme,
      ),
      _DesktopWorkspaceIconButton(
        tooltip: 'الملف الشخصي',
        icon: CupertinoIcons.person_crop_circle,
        selectedIcon: CupertinoIcons.person_crop_circle_fill,
        selected: activeSection == DesktopWorkspaceSection.profile,
        isDark: isDark,
        accentColor: accentColor,
        onPressed: onOpenProfile,
      ),
      _DesktopWorkspaceIconButton(
        tooltip: 'تسجيل الخروج',
        icon: CupertinoIcons.square_arrow_right,
        selectedIcon: CupertinoIcons.square_arrow_right_fill,
        isDark: isDark,
        accentColor: const Color(0xFFEF4444),
        onPressed: onLogout,
      ),
    ];

    Widget buildDivider() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Container(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      );
    }

    return Container(
      width: 76,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF161618)
            : const Color(0xFFF8F9FA),
        border: Border(
          left: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            _DesktopWorkspaceUserPill(
              user: user,
              displayName: displayName,
              isDark: isDark,
              accentColor: accentColor,
              onTap: onOpenProfile,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    ...mainActions.map(
                      (btn) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: btn,
                      ),
                    ),
                    if (opsActions.isNotEmpty) ...[
                      buildDivider(),
                      ...opsActions.map(
                        (btn) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: btn,
                        ),
                      ),
                    ],
                    buildDivider(),
                    ...bottomActions.map(
                      (btn) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: btn,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

class _DesktopWorkspaceUserPill extends StatelessWidget {
  const _DesktopWorkspaceUserPill({
    required this.user,
    required this.displayName,
    required this.isDark,
    required this.accentColor,
    this.onTap,
  });

  final AppUser? user;
  final String displayName;
  final bool isDark;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: displayName,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.35 : 0.22),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: isDark ? 0.16 : 0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SafeNetworkAvatar(
            radius: 20,
            backgroundColor: accentColor.withValues(alpha: 0.15),
            imageUrl: user?.avatarUrl,
            fallbackText: displayName.isEmpty
                ? '?'
                : displayName.substring(0, 1).toUpperCase(),
            fallbackTextStyle: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopWorkspaceIconButton extends StatefulWidget {
  const _DesktopWorkspaceIconButton({
    required this.tooltip,
    required this.icon,
    this.selectedIcon,
    required this.isDark,
    required this.accentColor,
    required this.onPressed,
    this.selected = false,
    this.accent = false,
    this.badgeCount = 0,
    this.hasPulsingBadge = false,
    this.customIconColor,
    this.statusColor,
  });

  final String tooltip;
  final int badgeCount;
  final bool hasPulsingBadge;
  final IconData icon;
  final IconData? selectedIcon;
  final bool isDark;
  final Color accentColor;
  final Color? customIconColor;
  final VoidCallback onPressed;
  final bool selected;
  final bool accent;
  final Color? statusColor;

  @override
  State<_DesktopWorkspaceIconButton> createState() =>
      _DesktopWorkspaceIconButtonState();
}

class _DesktopWorkspaceIconButtonState
    extends State<_DesktopWorkspaceIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final isDark = widget.isDark;
    final accentColor = widget.accentColor;

    // Apple minimalist translucent tile colors
    final Color bgColor;
    final Color borderColor;
    if (selected) {
      bgColor = accentColor.withValues(alpha: isDark ? 0.2 : 0.12);
      borderColor = accentColor.withValues(alpha: isDark ? 0.35 : 0.25);
    } else if (_hovered) {
      bgColor = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.05);
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.06);
    } else {
      bgColor = Colors.transparent;
      borderColor = Colors.transparent;
    }

    final Color iconColor;
    if (widget.customIconColor != null) {
      iconColor = widget.customIconColor!;
    } else if (selected) {
      iconColor = accentColor;
    } else if (widget.accent) {
      iconColor = accentColor.withValues(alpha: 0.95);
    } else {
      iconColor = isDark
          ? const Color(0xFF94A3B8) // Slate 400
          : const Color(0xFF64748B); // Slate 500
    }

    final activeIcon = (selected && widget.selectedIcon != null)
        ? widget.selectedIcon!
        : widget.icon;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: selected ? null : widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.93 : (_hovered ? 1.05 : 1.0),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: bgColor,
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(activeIcon, size: 22, color: iconColor),
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48), // Apple rose red
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE11D48).withValues(alpha: 0.35),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.hasPulsingBadge)
                    const Positioned(
                      top: 3,
                      right: 3,
                      child: _PulsingUpdateBadge(),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    bottom: selected ? 4 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: selected ? 16 : 0,
                      height: 2.5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: accentColor,
                      ),
                    ),
                  ),
                  if (widget.statusColor != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.statusColor,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFFF6F6F6),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopWorkspaceConnectionIcon extends ConsumerStatefulWidget {
  const _DesktopWorkspaceConnectionIcon({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_DesktopWorkspaceConnectionIcon> createState() =>
      _DesktopWorkspaceConnectionIconState();
}

class _DesktopWorkspaceConnectionIconState
    extends ConsumerState<_DesktopWorkspaceConnectionIcon> {
  bool _hovered = false;

  void _onTap() {
    ref.invalidate(chatSocketConnectionProvider);
  }

  void _onSecondaryTap() {
    ServerSettingsDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(chatRealtimeControllerProvider);
    final isConnected =
        connectionState.status == ChatConnectionStatus.connected;
    final isConnecting =
        connectionState.status == ChatConnectionStatus.connecting ||
        connectionState.status == ChatConnectionStatus.reconnecting;

    final color = isConnected
        ? const Color(0xFF10B981) // Green
        : isConnecting
        ? const Color(0xFFF59E0B) // Amber
        : const Color(0xFFEF4444); // Red

    final tooltip = isConnected
        ? 'متصل (اضغط للتحديث)'
        : isConnecting
        ? 'جاري الاتصال...'
        : 'غير متصل (اضغط للاتصال)';

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _onTap,
          onSecondaryTap: _onSecondaryTap,
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: _hovered
                  ? (widget.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.04))
                  : Colors.transparent,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  CupertinoIcons.antenna_radiowaves_left_right,
                  size: 18,
                  color: widget.isDark
                      ? Colors.white70
                      : const Color(0xFF728397),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: widget.isDark
                            ? const Color(0xFF1C1C1E)
                            : const Color(0xFFF6F6F6),
                        width: 1.5,
                      ),
                      boxShadow: _hovered
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarConnectionStatus extends ConsumerStatefulWidget {
  const _SidebarConnectionStatus();

  @override
  ConsumerState<_SidebarConnectionStatus> createState() =>
      _SidebarConnectionStatusState();
}

class _SidebarConnectionStatusState
    extends ConsumerState<_SidebarConnectionStatus> {
  bool _hovered = false;

  void _onTap() {
    final connectionState = ref.read(chatRealtimeControllerProvider);
    if (connectionState.status != ChatConnectionStatus.connected) {
      ref.read(chatRealtimeControllerProvider.notifier).reconnect();
    }
  }

  void _onSecondaryTap() {
    ServerSettingsDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(chatRealtimeControllerProvider);
    final isConnected =
        connectionState.status == ChatConnectionStatus.connected;
    final isConnecting =
        connectionState.status == ChatConnectionStatus.connecting ||
        connectionState.status == ChatConnectionStatus.reconnecting;

    final color = isConnected
        ? const Color(0xFF10B981)
        : isConnecting
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);

    final tooltip = isConnected
        ? 'متصل بالسيرفر'
        : isConnecting
        ? 'جاري الاتصال...'
        : 'غير متصل';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _onTap,
          onSecondaryTap: _onSecondaryTap,
          child: Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered
                  ? (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.04))
                  : Colors.transparent,
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.32),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    isConnected
                        ? 'assets/images/server-online.png'
                        : 'assets/images/server-down.png',
                    key: ValueKey(isConnected),
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingUpdateBadge extends StatefulWidget {
  const _PulsingUpdateBadge();

  @override
  State<_PulsingUpdateBadge> createState() => _PulsingUpdateBadgeState();
}

class _PulsingUpdateBadgeState extends State<_PulsingUpdateBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 2.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.85, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEF4444).withValues(alpha: _opacityAnimation.value),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEF4444),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
