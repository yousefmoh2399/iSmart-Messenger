import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';

void main() {
  group('SessionPersistence Tests', () {
    test('StoredAuthSession correctly serializes and deserializes', () {
      const session = StoredAuthSession(
        accessToken: 'abc',
        refreshToken: 'def',
        userId: '123',
        generation: 3,
      );

      final json = session.toJson();
      expect(json['accessToken'], equals('abc'));
      expect(json['refreshToken'], equals('def'));
      expect(json['userId'], equals('123'));
      expect(json['generation'], equals(3));

      final deserialized = StoredAuthSession.fromJson(json);
      expect(deserialized.accessToken, equals('abc'));
      expect(deserialized.refreshToken, equals('def'));
      expect(deserialized.userId, equals('123'));
      expect(deserialized.generation, equals(3));
    });

    test('StoredAuthSession handles legacy/null generation safely', () {
      final json = {
        'accessToken': 'abc',
        'refreshToken': 'def',
        'userId': '123',
        'generation': null,
      };

      final deserialized = StoredAuthSession.fromJson(json);
      expect(deserialized.generation, equals(0));
    });
  });
}
