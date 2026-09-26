import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test url', () {
    final baseUrl = 'http://192.168.1.100:3000/api/v1';
    final uri = Uri.parse(baseUrl);
    final socketUrl = uri.origin;
    print('Socket URL: $socketUrl');
  });
}
