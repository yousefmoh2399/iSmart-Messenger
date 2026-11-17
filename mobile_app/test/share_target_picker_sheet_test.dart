import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';
import 'package:mobile_app/features/chat/presentation/chat_overview_controller.dart';
import 'package:mobile_app/features/chat/presentation/widgets/share_target_picker_sheet.dart';
import 'package:mobile_app/shared/providers/providers.dart';
import 'package:mobile_app/shared/services/android_share_receiver.dart';

class FakeChatOverviewController extends ChatOverviewController {
  FakeChatOverviewController(this._data);
  final ChatOverviewData _data;

  @override
  Future<ChatOverviewData> build() async => _data;

  @override
  Future<void> ensureAllUsersLoaded() async {}
}

void main() {
  group('ShareTarget Model Tests', () {
    test('ShareTarget equality is based on unique ID', () {
      const target1 = ShareTarget(
        id: 'user_1',
        kind: ShareTargetKind.user,
        title: 'أحمد علي',
      );
      const target2 = ShareTarget(
        id: 'user_1',
        kind: ShareTargetKind.user,
        title: 'أحمد علي المحدث',
      );
      const target3 = ShareTarget(
        id: 'user_2',
        kind: ShareTargetKind.user,
        title: 'أحمد علي',
      );

      expect(target1, equals(target2));
      expect(target1.hashCode, equals(target2.hashCode));
      expect(target1, isNot(equals(target3)));
    });
  });

  group('ShareTargetPickerSheet Widget Tests', () {
    const currentUserId = 'user_me';

    final testDepartment = DepartmentSummary(
      id: 'dept_1',
      name: 'تقنية المعلومات',
      code: 'IT',
      description: 'قسم التكنولوجيا',
      managers: const [],
      membersCount: 2,
      defaultConversationId: null,
    );

    final userMe = ChatDirectoryUser(
      id: currentUserId,
      username: 'me',
      fullName: 'أنا المستخدم',
      jobTitle: 'المدير',
      role: 'admin',
      departmentId: 'dept_1',
      branchId: 'b_cairo',
      branchCode: 'CAI',
      isOnline: true,
      presenceStatus: 'online',
      isActive: true,
      avatarUrl: null,
      lastSeen: null,
      lastActiveAt: null,
    );

    final userAhmed = ChatDirectoryUser(
      id: 'user_ahmed',
      username: 'ahmed',
      fullName: 'أحمد علي',
      jobTitle: 'مهندس برمجيات',
      role: 'developer',
      departmentId: 'dept_1',
      branchId: 'b_cairo',
      branchCode: 'CAI',
      isOnline: true,
      presenceStatus: 'online',
      isActive: true,
      avatarUrl: null,
      lastSeen: null,
      lastActiveAt: null,
    );

    final userSara = ChatDirectoryUser(
      id: 'user_sara',
      username: 'sara',
      fullName: 'سارة محمد',
      jobTitle: 'مصممة واجهات',
      role: 'designer',
      departmentId: 'dept_1',
      branchId: 'b_alex',
      branchCode: 'ALX',
      isOnline: false,
      presenceStatus: 'offline',
      isActive: true,
      avatarUrl: null,
      lastSeen: null,
      lastActiveAt: null,
    );

    final convDirect = ChatConversation(
      id: 'conv_direct_1',
      name: '',
      type: 'direct',
      members: [userMe, userAhmed],
      description: '',
      departmentId: null,
      createdBy: currentUserId,
      admins: const [],
      broadcastPublisherIds: const [],
      blockedMemberIds: const [],
      pinnedMessage: null,
      lastMessage: ChatLastMessage(
        id: 'm1',
        content: 'أهلاً بك',
        senderId: userAhmed.id,
        senderName: userAhmed.fullName,
        messageType: 'text',
        seenBy: const [],
        deliveredTo: const [],
        status: 'read',
        createdAt: DateTime.now(),
      ),
      unreadCount: 0,
      isArchived: false,
      isMuted: false,
      isPinned: false,
      isFavorite: false,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final convGroup = ChatConversation(
      id: 'conv_group_1',
      name: 'فريق العمليات',
      type: 'group',
      members: [userMe, userSara],
      description: 'مجموعة التنسيق الداخلي',
      departmentId: null,
      createdBy: currentUserId,
      admins: const [],
      broadcastPublisherIds: const [],
      blockedMemberIds: const [],
      pinnedMessage: null,
      lastMessage: null,
      unreadCount: 0,
      isArchived: false,
      isMuted: false,
      isPinned: false,
      isFavorite: false,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final overviewData = ChatOverviewData(
      conversations: [convDirect, convGroup],
      manageableConversations: const [],
      users: [userAhmed, userSara],
      departments: [testDepartment],
      branches: const [],
      roles: const [],
    );

    testWidgets('Renders all sections: Saved Messages, Recent Chats, and All Directory Users', (tester) async {
      final sharedContent = AndroidSharedContent(
        text: 'ملاحظة مهمة للاجتماع',
        paths: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatOverviewControllerProvider.overrideWith(
              () => FakeChatOverviewController(overviewData),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ShareTargetPickerSheet(
                content: sharedContent,
                currentUserId: currentUserId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top Header
      expect(find.text('إرسال إلى...'), findsOneWidget);
      expect(find.text('اختر جهة اتصال أو أكثر للمشاركة'), findsOneWidget);

      // Pinned Saved Messages
      expect(find.text('الرسائل المحفوظة (أنت)'), findsOneWidget);

      // Recent Chats Section
      expect(find.text('المحادثات الأخيرة'), findsOneWidget);
      expect(find.text('فريق العمليات'), findsOneWidget);

      // Directory Users Section
      expect(find.text('جهات الاتصال / كافة المستخدمين'), findsOneWidget);
      expect(find.text('سارة محمد'), findsOneWidget);
      expect(find.text('أحمد علي'), findsWidgets);
    });

    testWidgets('Multi-selection toggles targets, shows count badge, and renders horizontal carousel strip', (tester) async {
      final sharedContent = AndroidSharedContent(
        text: 'صورة وثيقة رسمية',
        paths: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatOverviewControllerProvider.overrideWith(
              () => FakeChatOverviewController(overviewData),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ShareTargetPickerSheet(
                content: sharedContent,
                currentUserId: currentUserId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Saved Messages
      await tester.tap(find.text('الرسائل المحفوظة (أنت)'));
      await tester.pumpAndSettle();

      // Header updates to show 1 selected
      expect(find.text('تم تحديد 1 وجهة'), findsOneWidget);
      // Carousel appears with "المحددون (1)"
      expect(find.text('المحددون (1)'), findsOneWidget);

      // Tap on Group Conversation to select a second target
      await tester.tap(find.text('فريق العمليات'));
      await tester.pumpAndSettle();

      // Header updates to show 2 selected
      expect(find.text('تم تحديد 2 وجهة'), findsOneWidget);
      expect(find.text('المحددون (2)'), findsOneWidget);

      // Tap "مسح الكل" to clear selections
      await tester.tap(find.text('مسح الكل'));
      await tester.pumpAndSettle();

      expect(find.text('اختر جهة اتصال أو أكثر للمشاركة'), findsOneWidget);
      expect(find.text('المحددون (2)'), findsNothing);
    });

    testWidgets('Search query filters both recent chats and directory users', (tester) async {
      final sharedContent = AndroidSharedContent(
        text: 'بحث شير',
        paths: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatOverviewControllerProvider.overrideWith(
              () => FakeChatOverviewController(overviewData),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ShareTargetPickerSheet(
                content: sharedContent,
                currentUserId: currentUserId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search for "سارة"
      final searchField = find.byType(TextField).last;
      await tester.enterText(searchField, 'سارة');
      await tester.pumpAndSettle();

      // Sara should be found
      expect(find.text('سارة محمد'), findsOneWidget);
      // Group "فريق العمليات" should be filtered out
      expect(find.text('فريق العمليات'), findsNothing);

      // Search for "العمليات"
      await tester.enterText(searchField, 'العمليات');
      await tester.pumpAndSettle();

      expect(find.text('فريق العمليات'), findsOneWidget);
      expect(find.text('سارة محمد'), findsNothing);
    });
  });
}
