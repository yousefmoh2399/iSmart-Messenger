import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/chat/models/chat_models.dart';
import 'package:desktop_app/shared/models/managed_user.dart';

void main() {
  group('Multi-Department Serialization & Persistence Tests', () {
    test('ChatDirectoryUser.fromJson parses multiple departments and handles maps or string ids', () {
      final json = {
        'id': 'user-123',
        'username': 'ahmed',
        'fullName': 'Ahmed Ali',
        'jobTitle': 'Senior Accountant',
        'role': 'user',
        'departmentId': 'dept-primary',
        'departmentIds': ['dept-primary', 'dept-secondary', {'_id': 'dept-tertiary', 'name': 'Audit'}],
        'branchId': 'branch-1',
        'branchCode': 'CAI',
        'isOnline': true,
        'presenceStatus': 'online',
        'isActive': true,
        'avatarUrl': null,
      };

      final user = ChatDirectoryUser.fromJson(json);

      expect(user.id, equals('user-123'));
      expect(user.jobTitle, equals('Senior Accountant'));
      expect(user.departmentId, equals('dept-primary'));
      expect(user.departmentIds, equals(['dept-primary', 'dept-secondary', 'dept-tertiary']));
      expect(user.allDepartmentIds, equals(['dept-primary', 'dept-secondary', 'dept-tertiary']));
    });

    test('ChatDirectoryUser.fromJson falls back to departmentId when departmentIds is empty', () {
      final json = {
        'id': 'user-456',
        'username': 'sarah',
        'fullName': 'Sarah Omar',
        'departmentId': 'dept-hr',
        'departmentIds': <dynamic>[],
      };

      final user = ChatDirectoryUser.fromJson(json);

      expect(user.departmentId, equals('dept-hr'));
      expect(user.departmentIds, equals(['dept-hr']));
      expect(user.allDepartmentIds, equals(['dept-hr']));
    });

    test('ChatDirectoryUser.copyWith preserves departmentIds and jobTitle on presence update', () {
      const original = ChatDirectoryUser(
        id: 'user-789',
        username: 'mohamed',
        fullName: 'Mohamed Tarek',
        jobTitle: 'Network Engineer',
        role: 'user',
        departmentId: 'dept-it',
        departmentIds: ['dept-it', 'dept-tech-support'],
        branchId: 'branch-cairo',
        branchCode: 'CAI',
        isOnline: true,
        presenceStatus: 'online',
        isActive: true,
        avatarUrl: null,
        lastSeen: null,
        lastActiveAt: null,
      );

      final updatedPresence = original.copyWith(
        isOnline: false,
        presenceStatus: 'offline',
      );

      expect(updatedPresence.id, equals('user-789'));
      expect(updatedPresence.isOnline, isFalse);
      expect(updatedPresence.presenceStatus, equals('offline'));
      // Crucial: departmentIds and jobTitle must NOT be wiped out!
      expect(updatedPresence.jobTitle, equals('Network Engineer'));
      expect(updatedPresence.departmentId, equals('dept-it'));
      expect(updatedPresence.departmentIds, equals(['dept-it', 'dept-tech-support']));
      expect(updatedPresence.allDepartmentIds, equals(['dept-it', 'dept-tech-support']));
    });

    test('ManagedUser.fromJson robustly parses allDepartmentIds from strings and maps', () {
      final json = {
        'id': 'm-user-1',
        'username': 'khaled',
        'fullName': 'Khaled Adel',
        'role': 'user',
        'departmentId': {'_id': 'dept-sales'},
        'departmentIds': [{'id': 'dept-sales'}, 'dept-marketing'],
        'branchId': 'b-1',
        'branchCode': 'ALX',
        'isOnline': false,
        'isActive': true,
        'permissions': {'canCreateRooms': true},
      };

      final managedUser = ManagedUser.fromJson(json);

      expect(managedUser.id, equals('m-user-1'));
      expect(managedUser.departmentId, equals('dept-sales'));
      expect(managedUser.departmentIds, equals(['dept-sales', 'dept-marketing']));
      expect(managedUser.allDepartmentIds, equals(['dept-sales', 'dept-marketing']));
    });
  });
}
