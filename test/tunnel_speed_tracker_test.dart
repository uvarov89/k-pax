import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/services/vpn_service.dart';

void main() {
  test('uses platform rates when present', () {
    final tracker = TunnelSpeedTracker();
    final speed = tracker.ingest(
      upRate: 1200,
      downRate: 3400,
      upTotal: 1200,
      downTotal: 3400,
    );
    expect(speed.upBytesPerSec, 1200);
    expect(speed.downBytesPerSec, 3400);
  });

  test('derives rates from totals when platform speeds stay zero', () async {
    final tracker = TunnelSpeedTracker();
    tracker.ingest(upRate: 0, downRate: 0, upTotal: 1000, downTotal: 2000);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final speed = tracker.ingest(
      upRate: 0,
      downRate: 0,
      upTotal: 3000,
      downTotal: 6000,
    );
    expect(speed.upBytesPerSec, greaterThan(0));
    expect(speed.downBytesPerSec, greaterThan(0));
    expect(speed.upBytesTotal, 3000);
    expect(speed.downBytesTotal, 6000);
  });
}
