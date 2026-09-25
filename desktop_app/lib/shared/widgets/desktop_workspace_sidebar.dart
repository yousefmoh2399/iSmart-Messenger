import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../models/app_user.dart';
import '../providers/providers.dart';
import 'safe_network_avatar.dart';
import 'server_settings_dialog.dart';
import '../../features/chat/presentation/chat_realtime_controller.dart';

enum DesktopWorkspaceSection {
  chat,
  files,
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
    required this.onOpenServers,
    this.showServersShortcut = true,
    required this.onOpenProfile,
    this.onOpenUpdates,
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
  final VoidCallback onOpenServers;
  final bool showServersShortcut;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenUpdates;
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

    final displayName = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim()
        : (user?.username ?? 'المستخدم');
    final actionButtons = <Widget>[
      _DesktopWorkspaceIconButton(
        tooltip: 'المحادثات',
        icon: Iconsax.message5,
        selected: activeSection == DesktopWorkspaceSection.chat,
        isDark: isDark,
        accentColor: accentColor,
        badgeCount: unreadCount,
        onPressed: onOpenChat,
      ),
      _DesktopWorkspaceIconButton(
        tooltip: switch (currentThemeMode) {
          ThemeMode.dark => 'الوضع الداكن',
          ThemeMode.system => 'الوضع الفاتح',
          ThemeMode.light => 'الوضع الفاتح',
        },
        icon: switch (currentThemeMode) {
          ThemeMode.dark => Icons.dark_mode_rounded,
          ThemeMode.system => Icons.light_mode_rounded,
          ThemeMode.light => Icons.light_mode_rounded,
        },
        isDark: isDark,
        accentColor: accentColor,
        accent: true,
        onPressed: onToggleTheme,
      ),
      _DesktopWorkspaceIconButton(
        tooltip: 'الملفات',
        icon: Iconsax.folder5,
        selected: activeSection == DesktopWorkspaceSection.files,
        isDark: isDark,
        accentColor: accentColor,
        onPressed: onOpenFiles,
      ),
      if (showServersShortcut)
        _DesktopWorkspaceIconButton(
          tooltip: 'السيرفرات',
          icon: Icons.dns_rounded,
          selected: activeSection == DesktopWorkspaceSection.servers,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenServers,
        ),
      _DesktopWorkspaceIconButton(
        tooltip: 'الملف الشخصي',
        icon: Icons.account_circle_rounded,
        selected: activeSection == DesktopWorkspaceSection.profile,
        isDark: isDark,
        accentColor: accentColor,
        onPressed: onOpenProfile,
      ),
      if (onOpenUpdates != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'التحديثات',
          icon: Icons.system_update_alt_rounded,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenUpdates!,
        ),
      if (onOpenSystemMonitor != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'مراقبة النظام',
          icon: Iconsax.monitor,
          selected: activeSection == DesktopWorkspaceSection.systemMonitor,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenSystemMonitor!,
        ),
      if (onOpenAdmin != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'لوحة الإدارة',
          icon: Icons.admin_panel_settings_rounded,
          selected: activeSection == DesktopWorkspaceSection.admin,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenAdmin!,
        ),
      if (onOpenPrinters != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'إدارة الطابعات',
          icon: Icons.print_rounded,
          selected: activeSection == DesktopWorkspaceSection.printers,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenPrinters!,
        ),

      // if (onOpenPurchaseRequests != null)
      //   _DesktopWorkspaceIconButton(
      //     tooltip: 'طلبات الشراء',
      //     icon: Icons.shopping_cart_checkout_rounded,
      //     selected: activeSection == DesktopWorkspaceSection.purchaseRequests,
      //     isDark: isDark,
      //     accentColor: accentColor,
      //     onPressed: onOpenPurchaseRequests!,
      //   ),
      _DesktopWorkspaceIconButton(
        tooltip: 'تذاكر الدعم',
        icon: Icons.support_agent_rounded,
        selected: activeSection == DesktopWorkspaceSection.tickets,
        isDark: isDark,
        accentColor: accentColor,
        onPressed: onOpenTickets,
      ),
      if (onOpenSnipeit != null)
        _DesktopWorkspaceIconButton(
          tooltip: 'Snipe-IT',
          icon: Icons.computer_rounded,
          selected: activeSection == DesktopWorkspaceSection.snipeit,
          isDark: isDark,
          accentColor: accentColor,
          onPressed: onOpenSnipeit!,
        ),
      _DesktopWorkspaceIconButton(
        tooltip: 'تسجيل الخروج',
        icon: Iconsax.logout5,
        isDark: isDark,
        accentColor: const Color(0xFFDC2626),
        onPressed: onLogout,
      ),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: 80,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.75)
                : const Color(0xFFF6F6F6).withValues(alpha: 0.85),
            border: Border(
              left: BorderSide(
                // In RTL, the right side of the window is visually right. If it's on the visual left, the border is on the right side of the sidebar. Wait, we want the border on the opposite side of the screen edge. If it's on the left, border should be on the right. In LTR, BorderSide(right: ...). In RTL? We can use `BorderDirectional(end: BorderSide(...))` but BoxDecoration uses `Border`. Let's just use `right` border assuming it's placed on the left.
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
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
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: actionButtons
                          .map(
                            (btn) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: btn,
                            ),
                          )
                          .toList(),
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

class _DesktopWorkspaceUserPill extends StatelessWidget {
  const _DesktopWorkspaceUserPill({
    required this.user,
    required this.displayName,
    required this.isDark,
    required this.accentColor,
  });

  final AppUser? user;
  final String displayName;
  final bool isDark;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeNetworkAvatar(
        radius: 22,
        backgroundColor: accentColor.withValues(alpha: 0.18),
        imageUrl: user?.avatarUrl,
        fallbackText: displayName.isEmpty
            ? '?'
            : displayName.substring(0, 1).toUpperCase(),
        fallbackTextStyle: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DesktopWorkspaceIconButton extends StatefulWidget {
  const _DesktopWorkspaceIconButton({
    required this.tooltip,
    required this.icon,
    required this.isDark,
    required this.accentColor,
    required this.onPressed,
    this.selected = false,
    this.accent = false,
    this.badgeCount = 0,
    this.statusColor,
  });

  final String tooltip;
  final int badgeCount;
  final IconData icon;
  final bool isDark;
  final Color accentColor;
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
    final accent = widget.accent;
    final isDark = widget.isDark;
    final accentColor = widget.accentColor;

    final bgColor = selected
        ? accentColor.withValues(alpha: isDark ? 0.15 : 0.1)
        : _hovered
        ? (isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04))
        : Colors.transparent;

    final iconColor = selected
        ? accentColor
        : accent
        ? accentColor.withValues(alpha: 0.95)
        : (isDark ? Colors.white70 : const Color(0xFF728397));

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
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
            scale: _pressed ? 0.92 : (_hovered ? 1.06 : 1.0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: selected ? 56 : 50,
              height: selected ? 56 : 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  16,
                ), // A slightly cleaner radius
                color: bgColor,
                // border: Border.all(color: borderColor), // not needed since it's transparent
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.icon, size: selected ? 24 : 22, color: iconColor),
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48), // Rose red
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF1F2C38)
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            '${widget.badgeCount}',
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
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      bottom: selected ? 6 : 2,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: selected ? 18 : 0,
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: accentColor,
                        ),
                      ),
                    ),
                  if (widget.statusColor != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.statusColor,
                          border: Border.all(
                            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF6F6F6),
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
  const _DesktopWorkspaceConnectionIcon({
    required this.isDark,
  });

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
    final isConnected = connectionState.status == ChatConnectionStatus.connected;
    final isConnecting = connectionState.status == ChatConnectionStatus.connecting || connectionState.status == ChatConnectionStatus.reconnecting;
    
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
                  Icons.dns_rounded,
                  size: 20,
                  color: widget.isDark ? Colors.white70 : const Color(0xFF728397),
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
                        color: widget.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF6F6F6),
                        width: 1.5,
                      ),
                      boxShadow: _hovered
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              )
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
