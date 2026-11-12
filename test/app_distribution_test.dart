import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/app/distribution.dart';

void main() {
  test('default channel allows APK self-update', () {
    expect(AppDistribution.playStore, isFalse);
    expect(AppDistribution.allowsApkSelfUpdate, isTrue);
    expect(AppDistribution.updatesViaStore, isFalse);
  });
}
