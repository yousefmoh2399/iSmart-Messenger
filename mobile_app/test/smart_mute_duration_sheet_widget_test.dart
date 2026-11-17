import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_mute_duration_sheet.dart';

void main() {
  testWidgets('SmartMuteDurationSheet renders options and returns correct duration',
      (WidgetTester tester) async {
    final conv = ChatConversation(
      id: 'c1',
      type: 'direct',
      name: 'أحمد علي',
      description: '',
      departmentId: null,
      createdBy: 'u1',
      members: const [],
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

    SmartMuteResult? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedResult = await showSmartMuteDurationSheet(
                  context: context,
                  conversation: conv,
                  currentUserId: 'u1',
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    // 1. Open sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify header and options exist
    expect(find.text('كتم إشعارات المحادثة'), findsOneWidget);
    expect(find.text('أحمد علي'), findsOneWidget);
    expect(find.text('8 ساعات'), findsOneWidget);
    expect(find.text('أسبوع واحد'), findsOneWidget);
    expect(find.text('دائماً'), findsOneWidget);
    expect(find.text('كتم الصوت'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);

    // 2. Select 'أسبوع واحد' and submit
    await tester.tap(find.text('أسبوع واحد'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('كتم الصوت'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.isAlways, isFalse);
    expect(selectedResult!.duration, equals(const Duration(days: 7)));
  });

  testWidgets('SmartMuteDurationSheet selecting always returns SmartMuteResult.always',
      (WidgetTester tester) async {
    final conv = ChatConversation(
      id: 'c2',
      type: 'group',
      name: 'فريق التطوير',
      description: '',
      departmentId: null,
      createdBy: 'u1',
      members: const [],
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

    SmartMuteResult? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedResult = await showSmartMuteDurationSheet(
                  context: context,
                  conversation: conv,
                  currentUserId: 'u1',
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Select 'دائماً'
    await tester.tap(find.text('دائماً'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('كتم الصوت'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.isAlways, isTrue);
    expect(selectedResult!.duration, isNull);
    expect(selectedResult!.toMutedUntil(), isNull);
  });

  testWidgets('SmartMuteDurationSheet tapping cancel returns null',
      (WidgetTester tester) async {
    final conv = ChatConversation(
      id: 'c3',
      type: 'direct',
      name: 'محمد',
      description: '',
      departmentId: null,
      createdBy: 'u1',
      members: const [],
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

    SmartMuteResult? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedResult = await showSmartMuteDurationSheet(
                  context: context,
                  conversation: conv,
                  currentUserId: 'u1',
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(selectedResult, isNull);
  });
}
