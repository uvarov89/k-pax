import 'package:flutter/foundation.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

class InstalledAppItem {
  const InstalledAppItem({
    required this.name,
    required this.packageName,
    this.icon,
  });

  final String name;
  final String packageName;
  final Uint8List? icon;
}

/// Packages that often break when forced through a foreign exit (banks, RU apps).
const suggestedBypassPackages = <String>[
  'ru.sberbankmobile',
  'com.idamob.tinkoff.android',
  'ru.vtb24.mobilebanking.android',
  'com.vivalabank.mobile',
  'ru.alfabank.mobile.android',
  'com.yandex.bank',
  'ru.ozon.app.android',
  'com.wildberries.ru',
  'ru.yandex.taxi',
  'com.vkontakte.android',
  'ru.ok.android',
];

class InstalledAppsCatalog {
  Future<List<InstalledAppItem>> load({bool withIcons = true}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return _demoApps();
    }

    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: true,
        excludeNonLaunchableApps: true,
        withIcon: withIcons,
      );
      final mapped = apps
          .map(
            (AppInfo app) => InstalledAppItem(
              name: app.name,
              packageName: app.packageName,
              icon: app.icon,
            ),
          )
          .where((app) => app.packageName.isNotEmpty)
          .toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      return mapped;
    } catch (e, st) {
      debugPrint('InstalledAppsCatalog error: $e\n$st');
      return _demoApps();
    }
  }

  List<InstalledAppItem> _demoApps() {
    return const [
      InstalledAppItem(name: 'Сбербанк', packageName: 'ru.sberbankmobile'),
      InstalledAppItem(
        name: 'Т‑Банк',
        packageName: 'com.idamob.tinkoff.android',
      ),
      InstalledAppItem(
        name: 'ВТБ',
        packageName: 'ru.vtb24.mobilebanking.android',
      ),
      InstalledAppItem(name: 'VK', packageName: 'com.vkontakte.android'),
      InstalledAppItem(name: 'Wildberries', packageName: 'com.wildberries.ru'),
      InstalledAppItem(name: 'Ozon', packageName: 'ru.ozon.app.android'),
      InstalledAppItem(name: 'Яндекс Go', packageName: 'ru.yandex.taxi'),
    ];
  }
}
