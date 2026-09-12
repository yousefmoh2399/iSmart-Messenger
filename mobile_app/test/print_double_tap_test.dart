import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class PrintActionTester {
  final Set<String> printingItemIds = <String>{};
  final Map<String, String> itemIdToClientRequestId = <String, String>{};
  int apiCallCount = 0;
  List<String> passedRequestIds = [];
  bool apiShouldSucceed = true;

  Future<void> triggerPrint(String itemId) async {
    if (printingItemIds.contains(itemId)) {
      return;
    }

    printingItemIds.add(itemId);

    final clientRequestId = itemIdToClientRequestId.putIfAbsent(
      itemId,
      () => const Uuid().v4(),
    );

    apiCallCount++;
    passedRequestIds.add(clientRequestId);

    // Simulate network delay
    await Future<void>.delayed(const Duration(milliseconds: 10));

    if (apiShouldSucceed) {
      itemIdToClientRequestId.remove(itemId);
    }
    printingItemIds.remove(itemId);
  }
}

void main() {
  group('Mobile Print Double-tap and Retry Lock Tests', () {
    test('Double-tap guard blocks multiple simultaneous print triggers', () async {
      final tester = PrintActionTester();
      
      // Trigger multiple times simultaneously
      final future1 = tester.triggerPrint('item-1');
      final future2 = tester.triggerPrint('item-1');
      final future3 = tester.triggerPrint('item-1');

      await Future.wait([future1, future2, future3]);

      // Only the first trigger should have proceeded to the api call
      expect(tester.apiCallCount, equals(1));
    });

    test('If print fails, the clientRequestId is retained for retry', () async {
      final tester = PrintActionTester();
      tester.apiShouldSucceed = false;

      // First print attempt (fails)
      await tester.triggerPrint('item-1');
      expect(tester.apiCallCount, equals(1));
      final firstRequestId = tester.passedRequestIds.first;
      expect(tester.itemIdToClientRequestId['item-1'], equals(firstRequestId));

      // Second print attempt (retry)
      await tester.triggerPrint('item-1');
      expect(tester.apiCallCount, equals(2));
      final secondRequestId = tester.passedRequestIds.last;
      
      // Should use the exact same request ID
      expect(secondRequestId, equals(firstRequestId));
    });

    test('If print succeeds, the clientRequestId is cleared and a new one is generated next time', () async {
      final tester = PrintActionTester();
      tester.apiShouldSucceed = true;

      // First print attempt (succeeds)
      await tester.triggerPrint('item-1');
      expect(tester.apiCallCount, equals(1));
      final firstRequestId = tester.passedRequestIds.first;
      expect(tester.itemIdToClientRequestId.containsKey('item-1'), isFalse);

      // Second print attempt (new print request)
      await tester.triggerPrint('item-1');
      expect(tester.apiCallCount, equals(2));
      final secondRequestId = tester.passedRequestIds.last;

      // Should be a different request ID
      expect(secondRequestId, isNot(equals(firstRequestId)));
    });
  });
}
