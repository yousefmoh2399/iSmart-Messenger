import 'package:desktop_app/core/network/ip_address_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes blank and URL inputs', () {
    expect(normalizeIpAddress(null), '');
    expect(normalizeIpAddress('  '), '');
    expect(
      normalizeIpAddress('https://printer.example.com:8443/status'),
      'printer.example.com',
    );
  });

  test('normalizes bracketed, zoned, and mapped IPv6 values', () {
    expect(normalizeIpAddress('[fe80::1]'), 'fe80::1');
    expect(normalizeIpAddress('fe80::1%en0'), 'fe80::1');
    expect(normalizeIpAddress('::ffff:192.168.1.20'), '192.168.1.20');
    expect(normalizeIpAddress('=ffff:10.0.0.4'), '10.0.0.4');
  });

  test('extracts IPv4 addresses and preserves native IPv6', () {
    expect(normalizeIpAddress('device=172.16.0.8:9100'), '172.16.0.8');
    expect(normalizeIpAddress('192.168.1.30:8080'), '192.168.1.30');
    expect(normalizeIpAddress('2001:db8::7'), '2001:db8::7');
  });
}
