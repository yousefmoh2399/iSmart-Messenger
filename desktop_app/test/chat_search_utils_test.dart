import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/chat/models/chat_models.dart';
import 'package:desktop_app/features/chat/utils/chat_search_utils.dart';

void main() {
  group('ChatSearchUtils.normalize', () {
    test('normalizes Alef forms (أ, إ, آ, ٱ -> ا)', () {
      expect(ChatSearchUtils.normalize('أحمد'), 'احمد');
      expect(ChatSearchUtils.normalize('إبراهيم'), 'ابراهيم');
      expect(ChatSearchUtils.normalize('آدم'), 'ادم');
      expect(ChatSearchUtils.normalize('ٱبن'), 'ابن');
    });

    test('normalizes Alef Maqsura (ى -> ي)', () {
      expect(ChatSearchUtils.normalize('علي'), 'علي');
      expect(ChatSearchUtils.normalize('على'), 'علي');
      expect(ChatSearchUtils.normalize('مصطفى'), 'مصطفي');
      expect(ChatSearchUtils.normalize('يحيى'), 'يحيي');
    });

    test('normalizes Taa Marbuta (ة -> ه)', () {
      expect(ChatSearchUtils.normalize('فاطمة'), 'فاطمه');
      expect(ChatSearchUtils.normalize('فاطمه'), 'فاطمه');
      expect(ChatSearchUtils.normalize('شركة'), 'شركه');
      expect(ChatSearchUtils.normalize('حمزة'), 'حمزه');
    });

    test('strips Tashkeel and Tatweel', () {
      expect(ChatSearchUtils.normalize('مُحَمَّدٌ'), 'محمد');
      expect(ChatSearchUtils.normalize('مـحـمـد'), 'محمد');
    });

    test('normalizes Hamza on Waw and Yaa', () {
      expect(ChatSearchUtils.normalize('مؤمن'), 'مومن');
      expect(ChatSearchUtils.normalize('رئيس'), 'رييس');
    });
  });

  group('ChatSearchUtils.matches', () {
    test('matches identical or normalized Arabic strings', () {
      expect(ChatSearchUtils.matches('أحمد علي', 'احمد'), isTrue);
      expect(ChatSearchUtils.matches('احمد على', 'علي'), isTrue);
      expect(ChatSearchUtils.matches('فاطمة الزهراء', 'فاطمه'), isTrue);
      expect(ChatSearchUtils.matches('مصطفى كامل', 'مصطفي'), isTrue);
    });

    test('matches multi-word tokens in any order', () {
      expect(ChatSearchUtils.matches('أحمد علي محمود', 'محمود احمد'), isTrue);
      expect(ChatSearchUtils.matches('مكتب الحسابات - القاهرة', 'القاهره حسابات'), isTrue);
    });

    test('returns false when a token is not present', () {
      expect(ChatSearchUtils.matches('أحمد علي', 'محمود'), isFalse);
      expect(ChatSearchUtils.matches('أحمد علي', 'احمد كمال'), isFalse);
    });

    test('empty query matches everything', () {
      expect(ChatSearchUtils.matches('أي نص', ''), isTrue);
      expect(ChatSearchUtils.matches('أي نص', '   '), isTrue);
    });
  });

  group('ChatSearchUtils.matchesUser', () {
    const user = ChatDirectoryUser(
      id: 'u1',
      username: 'ahmed_ali',
      fullName: 'أحمد علي حسن',
      jobTitle: 'مهندس برمجيات',
      role: 'user',
      departmentId: 'dept1',
      departmentIds: ['dept1'],
      branchId: 'br1',
      branchCode: 'CAI',
      isOnline: true,
      presenceStatus: 'online',
      isActive: true,
      avatarUrl: null,
      lastSeen: null,
      lastActiveAt: null,
    );

    const primaryDept = DepartmentSummary(
      id: 'dept1',
      name: 'قسم تكنولوجيا المعلومات',
      code: 'IT',
      description: 'قسم تكنولوجيا المعلومات',
      managers: [],
      membersCount: 5,
      defaultConversationId: null,
    );

    const branch = BranchSummary(
      id: 'br1',
      name: 'فرع المعادي',
      code: 'CAI',
      description: 'فرع المعادي الرئيسي',
      membersCount: 20,
    );

    test('matches by normalized name', () {
      expect(
        ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDept,
          branch: branch,
          query: 'احمد',
        ),
        isTrue,
      );
      expect(
        ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDept,
          branch: branch,
          query: 'على',
        ),
        isTrue,
      );
    });

    test('matches by job title', () {
      expect(
        ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDept,
          branch: branch,
          query: 'مهندس',
        ),
        isTrue,
      );
    });

    test('matches by department name or code', () {
      expect(
        ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDept,
          branch: branch,
          query: 'تكنولوجيا',
        ),
        isTrue,
      );
      expect(
        ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDept,
          branch: branch,
          query: 'IT',
        ),
        isTrue,
      );
    });

    test('matches by branch name or code', () {
      expect(
        ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDept,
          branch: branch,
          query: 'المعادي',
        ),
        isTrue,
      );
      expect(
        ChatSearchUtils.matchesUser(
          user: user,
          primaryDepartment: primaryDept,
          branch: branch,
          query: 'CAI',
        ),
        isTrue,
      );
    });
  });

  group('ChatSearchUtils.matchesConversation', () {
    final conversation = ChatConversation(
      id: 'c1',
      type: 'direct',
      name: '',
      description: 'مناقشة المشاريع',
      departmentId: null,
      createdBy: 'u2',
      members: const [
        ChatDirectoryUser(
          id: 'u1',
          username: 'current_user',
          fullName: 'المستخدم الحالي',
          role: 'user',
          departmentId: null,
          branchId: 'b1',
          branchCode: 'CAI',
          isOnline: true,
          presenceStatus: 'online',
          isActive: true,
          avatarUrl: null,
          lastSeen: null,
          lastActiveAt: null,
        ),
        ChatDirectoryUser(
          id: 'u2',
          username: 'tariq_sayed',
          fullName: 'طارق سيد',
          jobTitle: 'مدير مشتريات',
          role: 'user',
          departmentId: null,
          branchId: 'b1',
          branchCode: 'CAI',
          isOnline: true,
          presenceStatus: 'online',
          isActive: true,
          avatarUrl: null,
          lastSeen: null,
          lastActiveAt: null,
        ),
      ],
      admins: const [],
      broadcastPublisherIds: const [],
      blockedMemberIds: const [],
      pinnedMessage: null,
      lastMessage: ChatLastMessage(
        content: 'تقرير المشتريات جاهز للاعتماد',
        senderId: 'u2',
        senderName: 'طارق سيد',
        messageType: 'text',
        createdAt: DateTime.now(),
      ),
      unreadCount: 2,
      isArchived: false,
      isMuted: false,
      isPinned: false,
      isFavorite: false,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('matches direct conversation by peer name and job title', () {
      expect(
        ChatSearchUtils.matchesConversation(
          conversation: conversation,
          query: 'طارق',
          currentUserId: 'u1',
        ),
        isTrue,
      );
      expect(
        ChatSearchUtils.matchesConversation(
          conversation: conversation,
          query: 'مشتريات',
          currentUserId: 'u1',
        ),
        isTrue,
      );
    });

    test('matches conversation by last message content', () {
      expect(
        ChatSearchUtils.matchesConversation(
          conversation: conversation,
          query: 'جاهز للاعتماد',
          currentUserId: 'u1',
        ),
        isTrue,
      );
    });

    test('returns false when no conversation fields match', () {
      expect(
        ChatSearchUtils.matchesConversation(
          conversation: conversation,
          query: 'مهندس صيانة',
          currentUserId: 'u1',
        ),
        isFalse,
      );
    });
  });
}
