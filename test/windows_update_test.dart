import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_vpn/core/services/windows_update.dart';

void main() {
  test('compares numeric versions and ignores a build suffix', () {
    expect(compareNumericVersions('1.0.8', '1.0.7'), 1);
    expect(compareNumericVersions('1.0.7', '1.0.8'), -1);
    expect(compareNumericVersions('1.0.8+10', '1.0.8'), 0);
    expect(compareNumericVersions('1.2', '1.2.0'), 0);
  });

  test('offers only a newer trusted installer', () {
    const current = '1.0.8';
    final newer = interpretWindowsUpdate(
      '{"version":"1.0.9","url":"https://github.com/uvarov89/k-pax/releases/download/v1.0.9-windows/K-Pax-Setup-1.0.9.exe"}',
      current,
    );
    expect(newer.status, WindowsUpdateStatus.newer);
    expect(newer.release?.version, '1.0.9');

    expect(
      interpretWindowsUpdate(
        '{"version":"1.0.8","url":"https://github.com/uvarov89/k-pax/releases/download/v1.0.8-windows/K-Pax-Setup-1.0.8.exe"}',
        current,
      ).status,
      WindowsUpdateStatus.current,
    );
    expect(
      interpretWindowsUpdate(
        '{"version":"1.0.9","url":"https://example.com/K-Pax-Setup.exe"}',
        current,
      ).status,
      WindowsUpdateStatus.unavailable,
    );
  });
}
