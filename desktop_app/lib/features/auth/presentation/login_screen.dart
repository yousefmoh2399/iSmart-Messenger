import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../app/desktop_workspace_shell.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../../shared/widgets/button_loading_indicator.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.initialErrorMessage,
    this.openServerSettingsOnStart = false,
  });

  final String? initialErrorMessage;
  final bool openServerSettingsOnStart;

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
  bool _didOpenServerSettingsOnStart = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialErrorMessage;
    _restoreRememberedUsername();
    if (widget.openServerSettingsOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didOpenServerSettingsOnStart) {
          return;
        }
        _didOpenServerSettingsOnStart = true;
        _showApiBaseUrlDialog(
          ref.read(apiBaseUrlControllerProvider).valueOrNull ??
              AppConfig.defaultApiBaseUrl,
        );
      });
    }
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
      return 'الحساب معطل من الإدارة. تواصل مع المسؤول.';
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
      return 'تعذر الاتصال بالخادم. تحقق من عنوان الخادم واتصال الشبكة ثم أعد المحاولة.';
    }
    if (text.contains('host') ||
        text.contains('dns') ||
        text.contains('api') ||
        text.contains('failed host lookup')) {
      return 'عنوان الخادم غير صحيح أو الخادم غير متاح حاليًا. عدّل الإعدادات ثم أعد المحاولة.';
    }
    return raw.trim().isEmpty ? 'فشل تسجيل الدخول. حاول مرة أخرى.' : raw;
  }

  Future<void> _showApiBaseUrlDialog(String currentBaseUrl) async {
    final controller = TextEditingController(text: currentBaseUrl);
    String? dialogError;
    bool isChecking = false;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final dialogWidth = (MediaQuery.sizeOf(dialogContext).width - 48)
              .clamp(320.0, 480.0)
              .toDouble();
          return AlertDialog(
            title: const Text('إعدادات الخادم'),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dialogWidth),
              child: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'عنوان API',
                        hintText: 'http://192.168.100.253',
                      ),
                      onChanged: (_) {
                        if (dialogError != null) {
                          setDialogState(() => dialogError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('سيتم فحص الاتصال بالخادم قبل حفظ العنوان.'),
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
                onPressed: isChecking
                    ? null
                    : () => Navigator.pop(dialogContext),
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
                        Navigator.pop(dialogContext, candidate);
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
          );
        },
      ),
    );

    if (result == null || !mounted) return;

    if (result == '__reset__') {
      await ref.read(apiBaseUrlControllerProvider.notifier).reset();
      try {
        final defaults = await ref
            .read(publicAppSettingsServiceProvider)
            .fetchDefaults();
        final desktopBaseUrl = defaults.desktopBaseUrl?.trim();
        if (desktopBaseUrl != null && desktopBaseUrl.isNotEmpty) {
          await ref
              .read(apiBaseUrlControllerProvider.notifier)
              .applyAdminDefault(desktopBaseUrl);
        }
      } catch (_) {}
    } else if (result.isNotEmpty) {
      await ref.read(apiBaseUrlControllerProvider.notifier).save(result);
    }

    await ref.read(authRepositoryProvider).clearLocalSessionForServerChange();
    ref.read(serverRecoveryRevisionProvider.notifier).state++;
    ref.invalidate(authControllerProvider);
    ref.invalidate(documentsControllerProvider);
    ref.invalidate(adminDocumentsControllerProvider);
    ref.invalidate(usersControllerProvider);
    await ref.read(serverConnectionControllerProvider.notifier).refresh();

    if (!mounted) return;
    setState(() => _errorMessage = null);
  }

  Widget _buildHeroPanel({required bool centered}) {
    return Padding(
      padding: EdgeInsets.all(centered ? 0 : 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
              ),
              child: Image.asset('assets/images/logo.png'),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'iSmart Messenger',
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'واجهة مكتبية حديثة لإدارة الملفات، متابعة المحادثات الداخلية، والوصول السريع إلى كل ما يخص حسابك من مكان واحد.',
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              color: Color(0xFFD9E6FF),
              fontSize: 16,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: centered ? WrapAlignment.center : WrapAlignment.start,
            spacing: 12,
            runSpacing: 12,
            children: const [
              _HeroPill(
                icon: Iconsax.mobile_programming,
                label: 'تطبيق موبايل',
              ),
              _HeroPill(icon: Iconsax.document, label: 'ملفات PDF'),
              _HeroPill(icon: Iconsax.message, label: 'شات داخلي'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard({
    required BuildContext context,
    required String currentBaseUrl,
    required AsyncValue<ServerConnectionState> serverConnection,
    required bool compact,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 520 : 430),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: isDark
              ? const Color(0xFF1F2C38).withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.8),
          border: Border.all(
            color: isDark
                ? const Color(0xFF314555).withValues(alpha: 0.45)
                : const Color(0xFFD8E1E8).withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Padding(
              padding: EdgeInsets.all(compact ? 22 : 28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'تسجيل الدخول',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'استخدم حسابك للوصول إلى الملفات والمحادثات.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? const Color(0xFF8B9FB4)
                            : const Color(0xFF5B6B7F),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'اسم المستخدم مطلوب'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Iconsax.lock),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword ? Iconsax.eye : Iconsax.eye_slash,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'كلمة المرور مطلوبة'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _rememberUsername,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('تذكر اسم المستخدم'),
                      subtitle: const Text(
                        'سنملأه تلقائيًا عند فتح التطبيق مرة أخرى.',
                      ),
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                _rememberUsername = value ?? false;
                              });
                            },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFB91C1C),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: ButtonLoadingIndicator(radius: 10),
                            )
                          : const Text('تسجيل الدخول'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _showApiBaseUrlDialog(currentBaseUrl),
                      icon: const Icon(Icons.settings_ethernet),
                      label: const Text('إعدادات الخادم'),
                    ),
                    const SizedBox(height: 14),
                    SelectableText(
                      'الخادم الحالي: $currentBaseUrl',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ServerConnectionIndicator(
                      state: serverConnection,
                      onRetry: () => ref
                          .read(serverConnectionControllerProvider.notifier)
                          .refresh(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUser = ref.watch(authControllerProvider).valueOrNull;
    if (authenticatedUser != null) {
      ref.watch(chatSocketConnectionProvider);
      ref.watch(chatRealtimeControllerProvider);
      web_bridge.electronDebugLog('login-screen', 'authenticated-fallback', {
        'userId': authenticatedUser.id,
        'username': authenticatedUser.username,
      });
      return const DesktopWorkspaceShell();
    }
    final apiBaseUrlState = ref.watch(apiBaseUrlControllerProvider);
    final serverConnection = ref.watch(serverConnectionControllerProvider);
    final currentBaseUrl =
        apiBaseUrlState.valueOrNull ?? AppConfig.defaultApiBaseUrl;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF08111D), Color(0xFF123A73), Color(0xFF1D4F9A)],
          ),
        ),
        child: SafeArea(
          minimum: EdgeInsets.all(1),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 980;
              return SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 120),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (compact) ...[
                          _buildHeroPanel(centered: true),
                          const SizedBox(height: 20),
                          _buildLoginCard(
                            context: context,
                            currentBaseUrl: currentBaseUrl,
                            serverConnection: serverConnection,
                            compact: true,
                          ),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: _buildHeroPanel(centered: false)),
                              const SizedBox(width: 28),
                              _buildLoginCard(
                                context: context,
                                currentBaseUrl: currentBaseUrl,
                                serverConnection: serverConnection,
                                compact: false,
                              ),
                            ],
                          ),
                        const SizedBox(height: 25),
                        const Text(
                          'Copyright © 2026 Yousef Mohamed. All rights reserved',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ServerConnectionIndicator extends StatelessWidget {
  const _ServerConnectionIndicator({
    required this.state,
    required this.onRetry,
  });

  final AsyncValue<ServerConnectionState> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String text, bool checking) = state.when(
      loading: () => (
        const Color(0xFFF59E0B),
        Icons.cloud_sync_rounded,
        'جارٍ فحص الاتصال بالخادم...',
        true,
      ),
      error: (error, _) => (
        const Color(0xFFDC2626),
        Icons.cloud_off_rounded,
        error.toString(),
        false,
      ),
      data: (value) => (
        value.isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        value.isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
        value.message,
        false,
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: checking ? null : onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
            if (checking)
              const SizedBox(
                width: 16,
                height: 16,
                child: ButtonLoadingIndicator(),
              )
            else
              Icon(Iconsax.refresh, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
