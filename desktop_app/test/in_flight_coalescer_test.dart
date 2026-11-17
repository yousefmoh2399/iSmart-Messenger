import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_app/core/network/in_flight_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runCoalescedInFlight', () {
    test(
      'coalesces concurrent callers without self-deadlock and clears inFlight',
      () async {
        final inFlight = <String, Future<Uint8List>>{};
        final completer = Completer<Uint8List>();
        var fetchCalls = 0;

        final futureA = runCoalescedInFlight(inFlight, 'avatar:u1', () {
          fetchCalls++;
          return completer.future;
        });
        final futureB = runCoalescedInFlight(inFlight, 'avatar:u1', () {
          fetchCalls++;
          return Future.value(Uint8List.fromList([9]));
        });

        expect(identical(futureA, futureB), isTrue);
        expect(fetchCalls, 1);
        expect(inFlight.containsKey('avatar:u1'), isTrue);

        final expected = Uint8List.fromList([137, 80, 78, 71]);
        completer.complete(expected);

        final results = await Future.wait([
          futureA,
          futureB,
        ]).timeout(const Duration(seconds: 1));

        expect(results[0], expected);
        expect(results[1], expected);
        expect(inFlight.containsKey('avatar:u1'), isFalse);
      },
    );

    test(
      'allows fresh request after previous coalesced fetch completes or fails',
      () async {
        final inFlight = <String, Future<int>>{};
        var calls = 0;

        // Synchronous throw must clear inFlight and propagate.
        await expectLater(
          runCoalescedInFlight(inFlight, 'k1', () {
            calls++;
            throw StateError('sync boom');
          }).timeout(const Duration(seconds: 1)),
          throwsStateError,
        );
        expect(calls, 1);
        expect(inFlight, isEmpty);

        // Async failure must clear inFlight and propagate to all waiters.
        final failCompleter = Completer<int>();
        final f1 = runCoalescedInFlight(inFlight, 'k1', () {
          calls++;
          return failCompleter.future;
        });
        final f2 = runCoalescedInFlight(inFlight, 'k1', () {
          calls++;
          return Future.value(99);
        });
        failCompleter.completeError(Exception('network down'));

        await expectLater(
          f1.timeout(const Duration(seconds: 1)),
          throwsException,
        );
        await expectLater(
          f2.timeout(const Duration(seconds: 1)),
          throwsException,
        );
        expect(calls, 2);
        expect(inFlight, isEmpty);

        // Subsequent fetch after failure executes normally.
        final recovered = await runCoalescedInFlight(inFlight, 'k1', () async {
          calls++;
          return 42;
        }).timeout(const Duration(seconds: 1));
        expect(recovered, 42);
        expect(calls, 3);
        expect(inFlight, isEmpty);
      },
    );

    test('runs distinct keys independently', () async {
      final inFlight = <String, Future<String>>{};
      var calls = 0;

      final results = await Future.wait([
        runCoalescedInFlight(inFlight, 'user-a', () async {
          calls++;
          return 'img-a';
        }),
        runCoalescedInFlight(inFlight, 'user-b', () async {
          calls++;
          return 'img-b';
        }),
      ]).timeout(const Duration(seconds: 1));

      expect(results, ['img-a', 'img-b']);
      expect(calls, 2);
      expect(inFlight, isEmpty);
    });
  });
}
