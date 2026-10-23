import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberUsername = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _restoreRememberedUsername();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreRememberedUsername() async {
    final repository = ref.read(authRepositoryProvider);
    final rememberEnabled = await repository.isRememberUsernameEnabled();
    final rememberedUsername = await repository.loadRememberedUsername();
    if (!mounted) {
      return;
    }
    setState(() {
      _rememberUsername = rememberEnabled;
      if ((rememberedUsername ?? '').trim().isNotEmpty) {
        _usernameController.text = rememberedUsername!.trim();
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            rememberUsername: _rememberUsername,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyLoginError(error));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _friendlyLoginError(Object error) {
    final raw = error.toString();
    final text = raw.toLowerCase();
    if (text.contains('invalid') &&
        (text.contains('password') || text.contains('credentials'))) {
      return 'اسم المستخدم أو كلمة المرور غير صحيحة.';
    }
    if (text.contains('disabled') ||
        text.contains('blocked') ||
        text.contains('inactive') ||
        text.contains('suspended') ||
        text.contains('معطل')) {
      return 'الحساب معطّل من الإدارة. تواصل مع المسؤول.';
    }
    if (text.contains('401') ||
        text.contains('unauthorized') ||
        text.contains('forbidden')) {
      return 'فشل تسجيل الدخول. تأكد من بيانات الحساب.';
    }
    if (text.contains('429') ||
        text.contains('too many') ||
        text.contains('attempt')) {
      return 'تم تجاوز عدد محاولات تسجيل الدخول. حاول مرة أخرى بعد قليل.';
    }
    if (text.contains('500') || text.contains('server')) {
      return 'الخادم يواجه مشكلة مؤقتة. حاول مرة أخرى بعد قليل.';
    }
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network') ||
        text.contains('timeout')) {
      return 'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى.';
    }
    return raw.trim().isEmpty ? 'فشل تسجيل الدخول. حاول مرة أخرى.' : raw;
  }

  Future<void> showApiBaseUrlDialogLegacy(String currentBaseUrl) async {
    await _showValidatedApiBaseUrlDialog(currentBaseUrl);
  }

  Future<void> _showValidatedApiBaseUrlDialog(String currentBaseUrl) async {
    final controller = TextEditingController(text: currentBaseUrl);
    String? dialogError;
    bool isChecking = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.dns_rounded,
                        size: 20,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إعدادات الخادم',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'تحديد عنوان خادم المؤسسة للربط',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Text field
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'monospace',
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      labelText: 'عنوان الخادم API',
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                      hintText: 'https://api.company.com أو 192.168.1.100:5000',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                      ),
                      border: InputBorder.none,
                    ),
                    onChanged: (_) {
                      if (dialogError != null) {
                        setDialogState(() => dialogError = null);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'استخدم الدومين أو العنوان الخاص بالسيرفر. إذا كتبت IP فقط سيتم استكمال http تلقائياً.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    height: 1.35,
                  ),
                ),

                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFFF3B30).withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_circle_fill,
                          size: 16,
                          color: Color(0xFFFF3B30),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFFFF3B30),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // Action buttons
                Row(
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF8E8E93),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onPressed: isChecking
                          ? null
                          : () async {
                              setDialogState(() {
                                dialogError = null;
                                isChecking = true;
                              });
                              final status = await ref
                                  .read(serverConnectionControllerProvider.notifier)
                                  .probe(AppConfig.defaultApiBaseUrl);
                              if (!dialogContext.mounted) return;
                              if (!status.isConnected) {
                                setDialogState(() {
                                  dialogError = status.message;
                                  isChecking = false;
                                });
                                return;
                              }
                              Navigator.pop(dialogContext, '__reset__');
                            },
                      child: const Text(
                        'إعادة الافتراضي',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.white70 : const Color(0xFF64748B),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onPressed: isChecking ? null : () => Navigator.pop(dialogContext),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      onPressed: isChecking
                          ? null
                          : () async {
                              final candidate = controller.text.trim();
                              if (candidate.isEmpty) {
                                setDialogState(() {
                                  dialogError = 'أدخل عنوان خادم صحيح أولاً.';
                                });
                                return;
                              }
                              setDialogState(() {
                                dialogError = null;
                                isChecking = true;
                              });
                              final status = await ref
                                  .read(serverConnectionControllerProvider.notifier)
                                  .probe(candidate);
                              if (!dialogContext.mounted) return;
                              if (!status.isConnected) {
                                setDialogState(() {
                                  dialogError = status.message;
                                  isChecking = false;
                                });
                                return;
                              }
                              Navigator.pop(dialogContext, status.baseUrl);
                            },
                      child: isChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: ButtonLoadingIndicator(),
                            )
                          : const Text(
                              'حفظ وتطبيق',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == null || !mounted) return;

    if (result == '__reset__') {
      await ref.read(apiBaseUrlControllerProvider.notifier).reset();
    } else if (result.isNotEmpty) {
      await ref.read(apiBaseUrlControllerProvider.notifier).save(result);
    }

    if (!mounted) return;

    ref.invalidate(authControllerProvider);
    ref.invalidate(remoteDocumentsControllerProvider);
    await ref.read(serverConnectionControllerProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _errorMessage = null);
  }

  String _cleanHostDisplay(String url) {
    if (url.isEmpty) return 'الخادم الافتراضي';
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        return uri.port != 0 && uri.port != 80 && uri.port != 443
            ? '${uri.host}:${uri.port}'
            : uri.host;
      }
    } catch (_) {}
    return url.replaceFirst(RegExp(r'^https?://'), '').replaceAll('/', '');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    final apiBaseUrlState = ref.watch(apiBaseUrlControllerProvider);
    final currentBaseUrl =
        apiBaseUrlState.valueOrNull ?? AppConfig.defaultApiBaseUrl;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final primaryColor = const Color(0xFF007AFF);
    final titleColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF64748B);

    final serverHostLabel = _cleanHostDisplay(currentBaseUrl);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Apple-style Ambient Glow at top
          Positioned(
            top: -100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      primaryColor.withValues(alpha: isDark ? 0.14 : 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 410),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Top Server Capsule Indicator (Apple Pill)
                      Center(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _showValidatedApiBaseUrlDialog(currentBaseUrl),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: borderColor, width: 0.8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.2 : 0.03,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF34C759), // Apple Green
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    serverHostLabel,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    CupertinoIcons.pencil,
                                    size: 13,
                                    color: primaryColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // 2. App Logo Container (Continuous Rounded Squircle)
                      Center(
                        child: Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: borderColor, width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.35 : 0.05,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                CupertinoIcons.chat_bubble_2_fill,
                                size: 42,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. Title & Subtitle (Apple Typography)
                      Text(
                        'iSmart Messenger',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'منظومة المراسلة والتعاون الذكي للمؤسسات',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: subtitleColor,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 4. Inset Grouped Credentials Card (Signature Apple Look)
                      Form(
                        key: _formKey,
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: borderColor, width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.04,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Username Field
                              TextFormField(
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'اسم المستخدم أو الكود الوظيفي',
                                  hintStyle: TextStyle(
                                    color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                                    fontSize: 14.5,
                                  ),
                                  prefixIcon: Icon(
                                    CupertinoIcons.person,
                                    size: 20,
                                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'يرجى إدخال اسم المستخدم'
                                        : null,
                              ),

                              // Hairline Apple Divider
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                indent: 48,
                                color: borderColor,
                              ),

                              // Password Field
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'كلمة المرور',
                                  hintStyle: TextStyle(
                                    color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                                    fontSize: 14.5,
                                  ),
                                  prefixIcon: Icon(
                                    CupertinoIcons.lock,
                                    size: 20,
                                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  ),
                                  suffixIcon: IconButton(
                                    splashRadius: 20,
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? CupertinoIcons.eye_slash
                                          : CupertinoIcons.eye,
                                      size: 20,
                                      color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                        ? 'يرجى إدخال كلمة المرور'
                                        : null,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 5. Remember Username Row (Apple iOS Switch Style)
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.checkmark_shield,
                              size: 20,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تذكر اسم المستخدم',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: titleColor,
                                    ),
                                  ),
                                  Text(
                                    'لحفظ الحساب والدخول السريع مستقبلاً',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w400,
                                      color: subtitleColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.85,
                              child: CupertinoSwitch(
                                value: _rememberUsername,
                                activeColor: primaryColor,
                                onChanged: (v) {
                                  setState(() => _rememberUsername = v);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 6. Error Message Callout (Apple Callout)
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withValues(
                              alpha: isDark ? 0.12 : 0.08,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFFF3B30).withValues(alpha: 0.25),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.exclamationmark_circle_fill,
                                size: 20,
                                color: Color(0xFFFF3B30),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF3B30),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 7. Primary Submit Button
                      Container(
                        margin: const EdgeInsets.only(top: 24),
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _isSubmitting ? null : _submit,
                          child: _isSubmitting
                              ? const CupertinoActivityIndicator(
                                  color: Colors.white,
                                  radius: 11,
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'تسجيل الدخول',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      CupertinoIcons.arrow_left,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // 8. Footer: Privacy Policy
                      Center(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: subtitleColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () async {
                            final url = currentBaseUrl.isNotEmpty
                                ? currentBaseUrl
                                : AppConfig.defaultApiBaseUrl;
                            final uri = Uri.parse(
                              url.endsWith('/')
                                  ? '${url}privacy-policy'
                                  : '$url/privacy-policy',
                            );
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          icon: Icon(
                            CupertinoIcons.shield_lefthalf_fill,
                            size: 15,
                            color: subtitleColor,
                          ),
                          label: Text(
                            'سياسة الخصوصية وأمان البيانات',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: subtitleColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '© 2026 iSmart Messenger • الإصدار المؤسسي الموحد',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
