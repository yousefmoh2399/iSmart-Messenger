import 'package:desktop_app/core/config/app_config.dart';
import 'package:desktop_app/features/chat/data/chat_draft_store.dart';
import 'package:desktop_app/shared/services/lan_file_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await const ChatDraftStore().clear('conv-perf-1');
  });

  test('ChatDraftStore coalesces rapid keystroke saves into single debounced write', () async {
    const store = ChatDraftStore();

    await store.save('conv-perf-1', 'h');
    await store.save('conv-perf-1', 'he');
    await store.save('conv-perf-1', 'hel');
    await store.save('conv-perf-1', 'hello');

    // Immediate in-memory load is already up to date before debounce flush
    expect(await store.load('conv-perf-1'), 'hello');

    // SharedPreferences should NOT have been written on every keystroke yet
    final prefsBeforeFlush = await SharedPreferences.getInstance();
    expect(prefsBeforeFlush.getString('chat_text_drafts_v1'), isNull);

    // Explicitly flush or wait past debounce
    await store.flush();
    expect(prefsBeforeFlush.getString('chat_text_drafts_v1'), contains('hello'));

    await store.clear('conv-perf-1');
    expect(await store.load('conv-perf-1'), isNull);
  });

  test('LanFileTransferService filters out VPN, TAP/TUN, and virtual adapters', () {
    expect(LanFileTransferService.isVirtualInterfaceName('OpenVPN TAP-Windows6'), isTrue);
    expect(LanFileTransferService.isVirtualInterfaceName('tun0'), isTrue);
    expect(LanFileTransferService.isVirtualInterfaceName('Fortinet SSL VPN'), isTrue);
    expect(LanFileTransferService.isVirtualInterfaceName('vEthernet (WSL)'), isTrue);
    expect(LanFileTransferService.isVirtualInterfaceName('Ethernet'), isFalse);
    expect(LanFileTransferService.isVirtualInterfaceName('Wi-Fi'), isFalse);
  });

  test('AppConfig fallbackAppVersion matches current 1.1.24 release', () {
    expect(AppConfig.fallbackAppVersion, '1.1.24');
  });
}
