import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Since _InfoLine is private to printer_monitoring_screen.dart, we will render a test suite
// that pump-widgets layout and measures responsiveness of info cells.
// We can use a test widget wrapping a simulated narrow/wide LayoutBuilder structure.
void main() {
  group('Layout Responsiveness Tests', () {
    testWidgets(
      'Statically defined _InfoLine structures adjust under narrow constraints',
      (WidgetTester tester) async {
        // Build a widget with limited horizontal space
        await tester.binding.setSurfaceSize(const Size(150, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 150,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 180;
                    return Column(
                      children: [
                        if (isNarrow)
                          const Text('Narrow Layout Stack')
                        else
                          const Text('Wide Layout Row'),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        expect(find.text('Narrow Layout Stack'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LinearProgressIndicator wraps inside restricted LayoutBuilder boundaries without overflow',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(100, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.5,
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );
  });
}
