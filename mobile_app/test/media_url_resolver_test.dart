import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/network/media_url_resolver.dart';

void main() {
  setUp(() {
    setMediaBaseUrl('https://api.example.com:8443');
  });

  tearDown(() {
    setMediaBaseUrl(AppConfig.defaultApiBaseUrl);
  });

  test('normalizes the runtime base URL', () {
    setMediaBaseUrl(' https://files.example.com/// ');
    expect(currentMediaBaseUrl, 'https://files.example.com');

    setMediaBaseUrl('not a url');
    expect(currentMediaBaseUrl, AppConfig.defaultApiBaseUrl);
  });

  test('returns null for absent media URLs', () {
    expect(resolveMediaUrl(null), isNull);
    expect(resolveMediaUrl('   '), isNull);
  });

  test('resolves relative paths against the current server', () {
    expect(
      resolveMediaUrl('uploads/avatar.png?size=small#profile'),
      'https://api.example.com:8443/uploads/avatar.png?size=small#profile',
    );
  });

  test('rebases local and server-owned absolute URLs', () {
    expect(
      resolveMediaUrl('http://localhost:3000/uploads/file.pdf?download=1'),
      'https://api.example.com:8443/uploads/file.pdf?download=1',
    );
    expect(
      resolveMediaUrl('https://old.example.com/api/users/avatar'),
      'https://api.example.com:8443/api/users/avatar',
    );
  });

  test('keeps public URLs and downgrades private HTTPS URLs', () {
    expect(
      resolveMediaUrl('https://cdn.example.com/images/logo.png'),
      'https://cdn.example.com/images/logo.png',
    );
    expect(
      resolveMediaUrl('https://192.168.1.25/media/file.png'),
      'http://192.168.1.25/media/file.png',
    );
  });

  test('returns malformed absolute input unchanged', () {
    const malformed = 'http://[::1';
    expect(resolveMediaUrl(malformed), malformed);
  });
}
