import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/providers/providers.dart';

/// Offline-resilient in-app Privacy Policy screen required for App Store review
/// when the workplace backend may not be reachable or before user sign-in.
class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  Future<void> _openInBrowser(BuildContext context, String baseUrl) async {
    final normalized = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.tryParse('${normalized}privacy-policy');
    if (uri == null) {
      return;
    }
    try {
      final canOpen = await canLaunchUrl(uri);
      if (canOpen && await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر فتح المتصفح أو الخادم غير متصل حالياً. يمكنك قراءة السياسة الكاملة هنا مباشرة.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl =
        ref.watch(apiBaseUrlControllerProvider).valueOrNull ??
        AppConfig.defaultApiBaseUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E5EA);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'سياسة الخصوصية وأمان البيانات',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'فتح النسخة الإلكترونية في المتصفح',
            icon: const Icon(CupertinoIcons.globe),
            onPressed: () => _openInBrowser(context, baseUrl),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF007AFF).withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.shield_lefthalf_fill,
                      color: Color(0xFF007AFF),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'iSmart Messenger • حماية الخصوصية',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'نلتزم بحماية سرية مراسلاتك ومستنداتك المؤسسية. التطبيق خالٍ تماماً من الإعلانات ومن أي تتبع تجاري أو مشاركة بيانات مع جهات تسويقية.',
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: subColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PolicySectionCard(
            cardColor: cardColor,
            borderColor: borderColor,
            subColor: subColor,
            icon: CupertinoIcons.doc_text_viewfinder,
            iconColor: const Color(0xFF34C759),
            title: '1. البيانات التي يتعامل معها التطبيق والأذونات',
            bullets: const [
              'الكاميرا: تُستخدم حصرياً لمسح المستندات الورقية ضوئياً (PDF) وقراءة أكواد QR والباركود الخاصة بأصول العمل، ولا يتم تشغيلها في الخلفية مطلقاً.',
              'الميكروفون: يُستخدم فقط عند ضغطك على زر التسجيل الصوتي داخل المحادثات.',
              'الصور والملفات: للوصول فقط إلى الملفات أو الصور التي تختارها لإرسالها أو حفظ المستندات الممسوحة في جهازك.',
              'الشبكة المحلية: للتواصل مع خادم العمل الداخلي أو الخادم السحابي المعتمد لديك.',
              'بيانات الحساب: اسم المستخدم، الاسم الكامل، الصورة الشخصية، ومعرف الجهاز للإشعارات (FCM / APNs) لتوصيل الرسائل الفورية.',
            ],
          ),
          const SizedBox(height: 12),
          _PolicySectionCard(
            cardColor: cardColor,
            borderColor: borderColor,
            subColor: subColor,
            icon: CupertinoIcons.lock_fill,
            iconColor: const Color(0xFF5856D6),
            title: '2. التشفير، التخزين الآمن، والإشعارات',
            bullets: const [
              'تُحفظ رموز الجلسة محلياً داخل مخزن المفاتيح المشفر بالنظام (iOS Keychain / Secure Storage).',
              'يتم نقل جميع الرسائل والملفات عبر اتصالات مشفرة (HTTPS / WSS).',
              'تُستخدم خدمة Firebase Cloud Messaging و Apple Push Notification service (APNs) فقط لإرسال تنبيهات الرسائل والمهام الفورية.',
              'لا نقوم ببيع أو تأجير أو مشاركة أي بيانات أو ملفات مع أي طرف ثالث إعلاني.',
            ],
          ),
          const SizedBox(height: 12),
          _PolicySectionCard(
            cardColor: cardColor,
            borderColor: borderColor,
            subColor: subColor,
            icon: CupertinoIcons.trash_fill,
            iconColor: const Color(0xFFDC2626),
            title: '3. حذف الحساب وإزالة البيانات نهائياً',
            bullets: const [
              'يمكنك حذف حسابك وجميع بياناتك ومحادثاتك مباشرة من داخل التطبيق عبر الانتقال إلى: الملف الشخصي والإعدادات > حذف الحساب نهائيًا.',
              'عند تأكيد الحذف، يتم إزالة حسابك ورسائلك المباشرة وملفاتك الشخصية وصورتك الرمزية ورموز الإشعارات نهائياً من الخادم وإنهاء الجلسة فوراً.',
              'يمكنك أيضاً التواصل مع مسؤول النظام في مؤسستك أو مراسلة الدعم الفني على: support@ismart.com.',
            ],
          ),
          const SizedBox(height: 12),
          _PolicySectionCard(
            cardColor: cardColor,
            borderColor: borderColor,
            subColor: subColor,
            icon: CupertinoIcons.person_2_fill,
            iconColor: const Color(0xFFFF9500),
            title: '4. خصوصية الأطفال والتواصل',
            bullets: const [
              'التطبيق موجه حصرياً لبيئات العمل المهنية للمستخدمين البالغين (18 عاماً فأكثر)، ولا يستهدف الأطفال ولا يجمع أي بيانات عنهم.',
              'للاستفسارات أو الدعم الفني: support@ismart.com',
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => _openInBrowser(context, baseUrl),
            icon: const Icon(CupertinoIcons.globe, size: 18),
            label: const Text(
              'فتح النسخة الإلكترونية في المتصفح',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySectionCard extends StatelessWidget {
  const _PolicySectionCard({
    required this.cardColor,
    required this.borderColor,
    required this.subColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.bullets,
  });

  final Color cardColor;
  final Color borderColor;
  final Color subColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in bullets) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: iconColor,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: subColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
