import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_models.dart';

enum MuteDurationOption {
  eightHours,
  oneWeek,
  always,
}

class SmartMuteResult {
  const SmartMuteResult.temporary(this.duration) : isAlways = false;

  const SmartMuteResult.always()
      : isAlways = true,
        duration = null;

  final bool isAlways;
  final Duration? duration;

  DateTime? toMutedUntil() {
    if (isAlways || duration == null) return null;
    return DateTime.now().add(duration!);
  }
}

/// WhatsApp / iOS-style smart mute duration sheet.
///
/// Returns [SmartMuteResult] if confirmed, or `null` if cancelled/dismissed.
Future<SmartMuteResult?> showSmartMuteDurationSheet({
  required BuildContext context,
  required ChatConversation conversation,
  required String currentUserId,
}) async {
  HapticFeedback.lightImpact();
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<SmartMuteResult?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _SmartMuteDurationSheetContent(
      conversation: conversation,
      currentUserId: currentUserId,
      isDark: isDark,
    ),
  );
}

class _SmartMuteDurationSheetContent extends StatefulWidget {
  const _SmartMuteDurationSheetContent({
    required this.conversation,
    required this.currentUserId,
    required this.isDark,
  });

  final ChatConversation conversation;
  final String currentUserId;
  final bool isDark;

  @override
  State<_SmartMuteDurationSheetContent> createState() =>
      _SmartMuteDurationSheetContentState();
}

class _SmartMuteDurationSheetContentState
    extends State<_SmartMuteDurationSheetContent> {
  MuteDurationOption _selectedOption = MuteDurationOption.eightHours;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final title = widget.conversation.displayTitle(widget.currentUserId);

    final bgCardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final surfaceColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textPrimary = isDark ? Colors.white : const Color(0xFF000000);
    final textSecondary =
        isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
    final accentColor = const Color(0xFFFF9500);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: bgCardColor.withValues(alpha: isDark ? 0.94 : 0.97),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2.25),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with icon & title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: isDark ? 0.2 : 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            CupertinoIcons.bell_slash_fill,
                            color: accentColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'كتم إشعارات المحادثة',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Options Group (iOS Inset Grouped Style)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildOptionTile(
                            title: '8 ساعات',
                            subtitle: 'كتم مؤقت لليوم الحالي',
                            option: MuteDurationOption.eightHours,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            accentColor: accentColor,
                            isFirst: true,
                            isLast: false,
                          ),
                          _buildDivider(isDark),
                          _buildOptionTile(
                            title: 'أسبوع واحد',
                            subtitle: 'كتم طوال الأسبوع الحالي',
                            option: MuteDurationOption.oneWeek,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            accentColor: accentColor,
                            isFirst: false,
                            isLast: false,
                          ),
                          _buildDivider(isDark),
                          _buildOptionTile(
                            title: 'دائماً',
                            subtitle: 'حتى تقوم بإلغاء الكتم يدويًا',
                            option: MuteDurationOption.always,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            accentColor: accentColor,
                            isFirst: false,
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Actions: Confirm & Cancel buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            onPressed: () => Navigator.pop(context, null),
                            child: Text(
                              'إلغاء',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            color: accentColor,
                            borderRadius: BorderRadius.circular(14),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              SmartMuteResult result;
                              switch (_selectedOption) {
                                case MuteDurationOption.eightHours:
                                  result = const SmartMuteResult.temporary(Duration(hours: 8));
                                  break;
                                case MuteDurationOption.oneWeek:
                                  result = const SmartMuteResult.temporary(Duration(days: 7));
                                  break;
                                case MuteDurationOption.always:
                                  result = const SmartMuteResult.always();
                                  break;
                              }
                              Navigator.pop(context, result);
                            },
                            child: const Text(
                              'كتم الصوت',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 16,
      endIndent: 16,
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06),
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required MuteDurationOption option,
    required Color textPrimary,
    required Color textSecondary,
    required Color accentColor,
    required bool isFirst,
    required bool isLast,
  }) {
    final isSelected = _selectedOption == option;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedOption = option);
      },
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(16) : Radius.zero,
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? accentColor : textSecondary.withValues(alpha: 0.4),
                  width: isSelected ? 6.5 : 1.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
