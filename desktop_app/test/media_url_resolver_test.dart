import 'package:desktop_app/core/config/app_config.dart';
import 'package:desktop_app/core/network/media_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('handles blank and relative URLs', () {
    expect(resolveMediaUrl(null), isNull);
    expect(resolveMediaUrl('  '), isNull);
    expect(resolveApiUrl('  '), '');
    expect(
      resolveApiUrl('uploads/avatar.png?size=small#profile'),
      'https://api.example.com:8443/uploads/avatar.png?size=small#profile',
    );
  });

  test('rebases local and server-owned absolute URLs', () {
    expect(
      resolveApiUrl('http://127.0.0.1:3000/uploads/file.pdf?download=1'),
      'https://api.example.com:8443/uploads/file.pdf?download=1',
    );
    expect(
      resolveApiUrl('https://old.example.com/api/users/avatar'),
      'https://api.example.com:8443/api/users/avatar',
    );
  });

  test('keeps public URLs and downgrades private HTTPS URLs', () {
    expect(
      resolveApiUrl('https://cdn.example.com/images/logo.png'),
      'https://cdn.example.com/images/logo.png',
    );
    expect(
      resolveApiUrl('https://10.10.0.5/media/file.png'),
      'http://10.10.0.5/media/file.png',
    );
  });

  test('returns malformed absolute input unchanged', () {
    const malformed = 'http://[::1';
    expect(resolveApiUrl(malformed), malformed);
  });
}
