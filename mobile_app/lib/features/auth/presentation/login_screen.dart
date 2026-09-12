import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final controller = TextEditingController(text: currentBaseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات الخادم'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'عنوان API',
                  hintText: 'https://api.company.com',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'على الهاتف الحقيقي استخدم الدومين أو Public IP الخاص بالخادم، وليس localhost.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, '__reset__'),
            child: const Text('إعادة الافتراضي'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    if (result == '__reset__') {
      await ref.read(apiBaseUrlControllerProvider.notifier).reset();
    } else if (result.isNotEmpty) {
      await ref.read(apiBaseUrlControllerProvider.notifier).save(result);
    }

    ref.invalidate(authControllerProvider);
    ref.invalidate(remoteDocumentsControllerProvider);
    setState(() => _errorMessage = null);
  }

  Future<void> _showValidatedApiBaseUrlDialog(String currentBaseUrl) async {
    final controller = TextEditingController(text: currentBaseUrl);
    String? dialogError;
    bool isChecking = false;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('إعدادات الخادم'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'عنوان API',
                    hintText: 'https://api.company.com أو 172.17.100.200:5000',
                  ),
                  onChanged: (_) {
                    if (dialogError != null) {
                      setDialogState(() => dialogError = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'على الهاتف الحقيقي استخدم الدومين أو Public IP الخاص بالخادم، وليس localhost. وإذا كتبت IP فقط فسيتم استكمال http تلقائيًا.',
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogError!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
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
                      if (!dialogContext.mounted) {
                        return;
                      }
                      if (!status.isConnected) {
                        setDialogState(() {
                          dialogError = status.message;
                          isChecking = false;
                        });
                        return;
                      }
                      Navigator.pop(dialogContext, '__reset__');
                    },
              child: const Text('إعادة الافتراضي'),
            ),
            TextButton(
              onPressed: isChecking ? null : () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isChecking
                  ? null
                  : () async {
                      final candidate = controller.text.trim();
                      if (candidate.isEmpty) {
                        setDialogState(() {
                          dialogError = 'أدخل عنوان خادم صحيح أولًا.';
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
                      if (!dialogContext.mounted) {
                        return;
                      }
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
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    if (result == '__reset__') {
      await ref.read(apiBaseUrlControllerProvider.notifier).reset();
    } else if (result.isNotEmpty) {
      await ref.read(apiBaseUrlControllerProvider.notifier).save(result);
    }

    if (!mounted) {
      return;
    }

    ref.invalidate(authControllerProvider);
    ref.invalidate(remoteDocumentsControllerProvider);
    await ref.read(serverConnectionControllerProvider.notifier).refresh();
    if (!mounted) {
      return;
    }
    setState(() => _errorMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    final apiBaseUrlState = ref.watch(apiBaseUrlControllerProvider);
    final isLoading = _isSubmitting;
    final currentBaseUrl =
        apiBaseUrlState.valueOrNull ?? AppConfig.defaultApiBaseUrl;

    // Minimalist Apple aesthetic
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark
        ? const Color(0xFFEBEBF5).withOpacity(0.6)
        : const Color(0xFF8E8E93);
    final primaryColor = const Color(0xFF007AFF);

    // Very soft gray background for inputs
    final inputFillColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Subtle elegant logo
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: inputFillColor,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        Icons.document_scanner_rounded,
                        size: 40,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'تسجيل الدخول',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'مرحباً بك مجدداً في مساحة العمل',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Login Form (No Card, directly on background)
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Username Field
                        TextFormField(
                          controller: _usernameController,
                          style: TextStyle(color: textColor, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'اسم المستخدم',
                            hintStyle: TextStyle(color: subtitleColor),
                            prefixIcon: Icon(
                              Icons.person_outline_rounded,
                              color: subtitleColor,
                              size: 22,
                            ),
                            filled: true,
                            fillColor: inputFillColor,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'مطلوب'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: textColor, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'كلمة المرور',
                            hintStyle: TextStyle(color: subtitleColor),
                            prefixIcon: Icon(
                              Icons.lock_outline_rounded,
                              color: subtitleColor,
                              size: 22,
                            ),
                            filled: true,
                            fillColor: inputFillColor,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),
                            suffixIcon: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: subtitleColor,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.isEmpty ? 'مطلوب' : null,
                        ),
                        const SizedBox(height: 16),

                        // Remember Me Checkbox
                        Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(unselectedWidgetColor: subtitleColor),
                          child: CheckboxListTile(
                            value: _rememberUsername,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: primaryColor,
                            checkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            title: Text(
                              'تذكر اسم المستخدم',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onChanged: (v) {
                              setState(() => _rememberUsername = v ?? false);
                            },
                          ),
                        ),

                        // Error Message
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFFF3B30),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFFFF3B30),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),

                        // Submit Button
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _isSubmitting ? null : _submit,
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: ButtonLoadingIndicator(),
                                  )
                                : const Text(
                                    'دخول',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Server Settings Button
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: subtitleColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () =>
                        _showValidatedApiBaseUrlDialog(currentBaseUrl),
                    icon: Icon(
                      Icons.settings_outlined,
                      color: subtitleColor,
                      size: 20,
                    ),
                    label: Text(
                      'إعدادات الخادم',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  // Server URL Display
                  if (currentBaseUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Server: $currentBaseUrl',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor.withOpacity(0.6),
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
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
