import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/settings/user_preferences.dart';
import 'package:mobile_app/features/auth/presentation/auth_controller.dart';
import 'package:mobile_app/features/profile/presentation/profile_screen.dart';
import 'package:mobile_app/shared/models/app_user.dart';
import 'package:mobile_app/shared/providers/providers.dart';

class FakeAuthController extends AuthController {
  FakeAuthController(this._user);
  final AppUser _user;

  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: _user,
      );

  @override
  Future<void> updateProfile({
    required String fullName,
    String? jobTitle,
    String? password,
  }) async {}
}

class FakeUserPreferencesController extends UserPreferencesController {
  @override
  Future<UserPreferences> build() async => UserPreferences.defaults();
}

void main() {
  group('ProfileScreen Widget Tests', () {
    final testUser = AppUser(
      id: 'u_101',
      username: 'yousef_dev',
      fullName: 'يوسف محمد',
      jobTitle: 'كبير مهندسي البرمجيات',
      role: 'admin',
      departmentId: 'dept_it',
      branchCode: 'CAI',
      branchId: 'b_1',
      isOnline: true,
      permissions: const {'canCreateUsers': true, 'canCreateDepartments': true},
      presenceStatus: 'online',
      isActive: true,
      avatarUrl: null,
      lastSeen: null,
      lastActiveAt: null,
      maxAttachmentSizeMB: 25,
      chatPreferences: ChatPreferences.defaults,
    );

    testWidgets('Renders all organized sections and user badges correctly when embedded in tab', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => FakeAuthController(testUser)),
            userPreferencesControllerProvider.overrideWith(FakeUserPreferencesController.new),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileScreen(isEmbeddedInTab: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hero Card User Info
      expect(find.text('يوسف محمد'), findsOneWidget);
      expect(find.text('كبير مهندسي البرمجيات'), findsOneWidget);
      expect(find.text('yousef_dev'), findsOneWidget);
      expect(find.text('مسؤول نظام'), findsOneWidget);
      expect(find.text('فرع CAI'), findsOneWidget);
      expect(find.text('متصل الآن'), findsOneWidget);

      // Action Buttons
      expect(find.text('تعديل البيانات'), findsOneWidget);
      expect(find.text('كلمة المرور'), findsOneWidget);

      // Section Titles
      expect(find.text('المظهر والعرض'), findsOneWidget);
      expect(find.text('المحادثات والتواصل'), findsOneWidget);
      expect(find.text('الإشعارات والتنبيهات'), findsOneWidget);
      expect(find.text('التخزين والملفات والذاكرة'), findsOneWidget);
      expect(find.text('الملفات والإنتاجية'), findsOneWidget);
      expect(find.text('الأدوات الإدارية والشبكة'), findsOneWidget);
      expect(find.text('عن المنظومة والأمان'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
    });

    testWidgets('Tapping "تعديل البيانات" opens the Edit Profile modal sheet', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => FakeAuthController(testUser)),
            userPreferencesControllerProvider.overrideWith(FakeUserPreferencesController.new),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileScreen(isEmbeddedInTab: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "تعديل البيانات"
      await tester.tap(find.text('تعديل البيانات'));
      await tester.pumpAndSettle();

      // Bottom sheet should open with title and save button
      expect(find.text('تعديل البيانات الشخصية'), findsOneWidget);
      expect(find.text('حفظ التعديلات'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'الاسم الكامل'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'المسمى الوظيفي'), findsOneWidget);
    });

    testWidgets('Tapping "كلمة المرور" opens the Change Password modal sheet', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => FakeAuthController(testUser)),
            userPreferencesControllerProvider.overrideWith(FakeUserPreferencesController.new),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileScreen(isEmbeddedInTab: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "كلمة المرور"
      await tester.tap(find.text('كلمة المرور'));
      await tester.pumpAndSettle();

      // Bottom sheet should open
      expect(find.text('تغيير كلمة المرور'), findsOneWidget);
      expect(find.text('تأكيد وتغيير كلمة المرور'), findsOneWidget);
    });

    testWidgets('Tapping "مجلدات الحفظ والتخزين" opens the folder management modal sheet', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => FakeAuthController(testUser)),
            userPreferencesControllerProvider.overrideWith(FakeUserPreferencesController.new),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileScreen(isEmbeddedInTab: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to Storage section
      await tester.scrollUntilVisible(
        find.text('مجلدات الحفظ والتخزين'),
        200,
      );
      await tester.pumpAndSettle();

      // Tap "مجلدات الحفظ والتخزين"
      await tester.tap(find.text('مجلدات الحفظ والتخزين'));
      await tester.pumpAndSettle();

      // Bottom sheet should open
      expect(find.text('تخصيص أماكن حفظ المستندات والملفات على جهازك'), findsOneWidget);
      expect(find.text('مجلد حفظ ملفات المسح (PDF)'), findsOneWidget);
      expect(find.text('مجلد تخزين المرفقات والصور'), findsOneWidget);
    });
  });
}
