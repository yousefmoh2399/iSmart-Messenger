import 'package:desktop_app/core/network/media_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio attachment API paths resolve to absolute URLs', () {
    setMediaBaseUrl('http://127.0.0.1:3000');

    final resolved = resolveMediaUrl(
      '/api/chat/messages/69f5a6fb453fd6951e4736bc/1784533132685-rw9q6i2x.m4a/file',
    );

    expect(
      resolved,
      'http://127.0.0.1:3000/api/chat/messages/69f5a6fb453fd6951e4736bc/1784533132685-rw9q6i2x.m4a/file',
    );
    expect(Uri.parse(resolved!).hasScheme, isTrue);
    expect(Uri.parse(resolved).host, isNotEmpty);
  });
}
