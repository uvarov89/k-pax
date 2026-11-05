import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/features/home/widgets/xplm_home_scene.dart';

void main() {
  testWidgets(
    'shield pulses only while busy and respects reduced motion and hidden tabs',
    (tester) async {
      Future<void> show({
        bool connected = false,
        bool busy = false,
        bool reduce = false,
        bool visible = true,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: TickerMode(
                enabled: visible,
                child: Center(
                  child: SizedBox(
                    width: 390,
                    height: 236,
                    child: XplmHomeScene(connected: connected, busy: busy),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      double scale() => tester
          .widget<Transform>(find.byKey(const ValueKey('xplm-shield-motion')))
          .transform
          .storage[0];

      await show();
      expect(scale(), 1);
      await show(busy: true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(scale(), greaterThan(1));
      expect(scale(), lessThanOrEqualTo(1.018));
      await show(connected: true);
      await tester.pumpAndSettle();
      expect(scale(), 1);
      expect(tester.hasRunningAnimations, isFalse);

      // Disconnecting uses the same busy flag, with connected=false.
      await show(busy: true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(scale(), greaterThan(1));
      await show();
      await tester.pumpAndSettle();
      expect(scale(), 1);
      expect(tester.hasRunningAnimations, isFalse);

      await show(busy: true, reduce: true);
      await tester.pump(const Duration(seconds: 2));
      expect(scale(), 1);
      expect(tester.hasRunningAnimations, isFalse);
      await show(busy: true, visible: false);
      await tester.pump(const Duration(seconds: 2));
      expect(scale(), 1);
      expect(tester.hasRunningAnimations, isFalse);
      await show(busy: true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(scale(), greaterThan(1));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
