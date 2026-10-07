import 'package:pulse_vpn/core/models/app_settings.dart';

class AppStrings {
  const AppStrings(this.lang);

  final AppLanguage lang;

  bool get isRu => lang == AppLanguage.ru;

  String get appName => 'K-Pax';
  String get settings => isRu ? 'Настройки' : 'Settings';
  String get simple => isRu ? 'Простой' : 'Simple';
  String get pro => isRu ? 'Подробно' : 'Details';
  String get connect => isRu ? 'Подключить' : 'Connect';
  String get disconnect => isRu ? 'Отключить' : 'Disconnect';
  String get connecting => isRu ? 'Подключение' : 'Connecting';
  String get disconnecting => isRu ? 'Отключение' : 'Disconnecting';
  String get retry => isRu ? 'Повторить' : 'Retry';
  String get notConnected => isRu ? 'Не подключено' : 'Not connected';
  String get connectingStatus => isRu ? 'Подключение…' : 'Connecting…';
  String get disconnectingStatus => isRu ? 'Отключение…' : 'Disconnecting…';
  String get connectionError =>
      isRu ? 'Ошибка подключения' : 'Connection error';
  String get connectFailed =>
      isRu ? 'Не удалось подключиться' : 'Failed to connect';
  String connectedTo(String place) =>
      isRu ? 'Подключено · $place' : 'Connected · $place';
  String get auto => isRu ? 'Авто' : 'Auto';
  String get country => isRu ? 'Страна' : 'Country';
  String get bestServerAuto =>
      isRu ? 'Лучший сервер автоматически' : 'Best server automatically';
  String selected(String name) => isRu ? 'Выбрано: $name' : 'Selected: $name';
  String get openProSettings =>
      isRu ? 'Параметры соединения' : 'Connection options';
  String get location => isRu ? 'Локация' : 'Location';
  String get recommended => isRu ? 'рекомендуется' : 'recommended';
  String get bestSpeedAuto => isRu
      ? 'Лучшая скорость автоматически'
      : 'Best speed automatically';
  String get proMode => isRu ? 'Соединение' : 'Connection';
  String get protocol => isRu ? 'Протокол' : 'Protocol';
  String get networkBypass => isRu ? 'Обход сети' : 'Network bypass';
  String get dns => 'DNS';
  String get dnsAutomatic => isRu ? 'Автоматически' : 'Automatic';
  String get splitTunneling =>
      isRu ? 'Приложения и VPN' : 'Apps & VPN';
  String get splitSoon => isRu
      ? 'Выберите, какие приложения идут через VPN'
      : 'Choose which apps use the VPN';
  String get splitSnack => isRu
      ? 'Откройте «Приложения и VPN» в настройках'
      : 'Open Apps & VPN in Settings';
  String get splitTunnelHint => isRu
      ? 'Некоторые банки и сервисы в РФ плохо работают через зарубежный выход. Их можно исключить из VPN.'
      : 'Some local banks and services break through a foreign exit. Exclude them from the VPN.';
  String get splitModeAll =>
      isRu ? 'Все приложения через VPN' : 'All apps through VPN';
  String get splitModeAllHint => isRu
      ? 'Весь трафик устройства в туннеле'
      : 'All device traffic goes through the tunnel';
  String get splitModeExclude =>
      isRu ? 'Исключить выбранные' : 'Exclude selected';
  String get splitModeExcludeHint => isRu
      ? 'Выбранные приложения ходят мимо VPN (рекомендуется для банков)'
      : 'Selected apps bypass the VPN (recommended for banks)';
  String get splitModeInclude =>
      isRu ? 'Только выбранные через VPN' : 'Only selected through VPN';
  String get splitModeIncludeHint => isRu
      ? 'VPN только для отмеченных приложений'
      : 'VPN only for checked apps';
  String get splitSearchHint =>
      isRu ? 'Поиск приложения' : 'Search apps';
  String get splitAddSuggested =>
      isRu ? 'Добавить банки/сервисы РФ' : 'Add RU banks/services';
  String get splitSuggestedAdded => isRu
      ? 'Добавлены найденные приложения из списка'
      : 'Added matching apps from the suggestion list';
  String get splitAllSelectedHint => isRu
      ? 'Список приложений не нужен: весь трафик идёт через VPN.'
      : 'No app list needed: all traffic uses the VPN.';
  String get splitAppliesNote => isRu
      ? 'Применится при следующем подключении native VPN. Сейчас настройка сохраняется.'
      : 'Applies on the next native VPN connect. Settings are saved now.';
  String splitSelectedCount(int n) =>
      isRu ? 'Выбрано: $n' : 'Selected: $n';
  String splitSubtitle(String mode, int n) =>
      isRu ? '$mode · $n прил.' : '$mode · $n apps';
  String get killSwitch => 'Kill switch';
  String get killSwitchHint => isRu
      ? 'Блокировать трафик при обрыве'
      : 'Block traffic if the tunnel drops';
  String get testNodes => isRu ? 'Тест нод' : 'Test nodes';
  String get testingNodes => isRu ? 'Тест нод…' : 'Testing nodes…';
  String get ipv6 => 'IPv6';
  String get protocolFallback =>
      isRu ? 'Fallback протоколов' : 'Protocol fallback';
  String get protocolFallbackHint => isRu
      ? 'REALITY ↔ Hysteria2 при недоступности'
      : 'REALITY ↔ Hysteria2 on failure';
  String get reconnect => isRu ? 'Переподключение' : 'Reconnect';
  String get sectionConnection => isRu ? 'Подключение' : 'Connection';
  String get sectionNotifications => isRu ? 'Уведомления' : 'Notifications';
  String get sectionAccount => isRu ? 'Аккаунт' : 'Account';
  String get sectionAppearance => isRu ? 'Внешний вид' : 'Appearance';
  String get sectionAbout => isRu ? 'О приложении' : 'About';
  String get autoConnectLaunch =>
      isRu ? 'Автоподключение при запуске' : 'Connect on launch';
  String get autoConnectWifi =>
      isRu ? 'При подключении к Wi‑Fi' : 'On Wi‑Fi connect';
  String get autoConnectMobile =>
      isRu ? 'При мобильной сети' : 'On mobile data';
  String get alwaysOnVpn => 'Always-on VPN';
  String get alwaysOnVpnHint => isRu
      ? 'Включается в системных настройках Android'
      : 'Enabled in Android system settings';
  String get openSystemVpnSettings =>
      isRu ? 'Как включить' : 'How to enable';
  String get rememberLastCountry =>
      isRu ? 'Запоминать последнюю страну' : 'Remember last country';
  String get connectionStatusNotif =>
      isRu ? 'Статус подключения' : 'Connection status';
  String get connectionStatusNotifHint => isRu
      ? 'Уведомления о подключении и обрыве'
      : 'Alerts for connect and disconnect';
  String get refreshServers =>
      isRu ? 'Обновить подписку' : 'Refresh subscription';
  String get refreshServersHint => isRu
      ? 'Заново получить серверы по вашей ссылке'
      : 'Fetch servers from your link again';
  String get pasteLinkTitle => isRu ? 'Почта, ник или ссылка' : 'Email, nick or link';
  String get pasteLinkBody => isRu
      ? 'Укажите почту или Telegram: доступ создаётся один раз. Если он уже есть, появится «Восстановить доступ». Свою ссылку или ссылку другого сервиса вставьте в это же поле.'
      : 'Enter an email or Telegram nick. Access is created once. If it already exists, Restore access appears. Paste your own link or another service link in the same field.';
  String get pasteLinkHint => isRu ? 'Почта, @ник или ссылка' : 'Email, @nick or link';
  String get saveLink => isRu ? 'Получить доступ' : 'Get access';
  String contactTaken(String number) => isRu
      ? 'Номер $number. Эта почта или ник уже используются.'
      : 'Account $number. This email or nick is already used.';
  String get restoreAccess => isRu ? 'Восстановить доступ' : 'Restore access';
  String get writeEmail => isRu ? 'Написать на почту' : 'Write an email';
  String get writeTelegram => isRu ? 'Написать в Telegram' : 'Write in Telegram';
  String get restoreHintEmail => isRu
      ? 'Откроется письмо на support@k-pax.space. Отправьте его с этой же почты.'
      : 'A message to support@k-pax.space opens. Send it from this same email.';
  String get restoreHintTelegram => isRu
      ? 'Напишите с этого же Telegram. Бот пришлёт ссылку и сколько дней осталось.'
      : 'Write from this same Telegram. The bot sends the link and the days left.';
  String get openProfileForAccess => isRu
      ? 'Почту или ник укажите в профиле'
      : 'Enter your email or nick in the profile';
  String get linkReadyTitle => isRu ? 'Доступ включён' : 'Access is on';
  String get linkReadyBody => isRu
      ? 'Ссылка сохранена в приложении. Скопируйте её для компьютера: второй раз мы её не покажем.'
      : 'The link is saved in the app. Copy it for your computer: it will not be shown again.';
  String get badLink => isRu
      ? 'Нужна ссылка с сайта, она начинается с https://sub.k-pax.space/s/'
      : 'Use the link from the site. It starts with https://sub.k-pax.space/s/';
  String get linkOpenFailed => isRu
      ? 'Ссылка не открылась. Проверьте интернет и попробуйте ещё раз.'
      : 'The link did not open. Check the internet and try again.';
  String get replaceLink => isRu ? 'Заменить ссылку' : 'Replace link';
  String get serversUpdated =>
      isRu ? 'Серверы обновлены' : 'Servers updated';
  String get accountSoon => isRu
      ? 'Подписка и устройства — после backend'
      : 'Subscription and devices — after backend';
  String get language => isRu ? 'Язык' : 'Language';
  String get theme => isRu ? 'Тема' : 'Theme';
  String get themeDark => isRu ? 'Тёмная' : 'Dark';
  String get themeLight => isRu ? 'Светлая' : 'Light';
  String get about => isRu ? 'О приложении' : 'About';
  String get version => isRu ? 'Версия' : 'Version';
  String get privacy => isRu ? 'Политика приватности' : 'Privacy policy';
  String get privacySoon => isRu
      ? 'Какие данные хранятся'
      : 'What data is stored';
  List<String> get privacyParagraphs => isRu
      ? const [
          'Чтобы выдать доступ, мы храним почту или ник Telegram, номер счёта, срок и технический ключ подключения.',
          'Этого хватает, чтобы создать доступ, вернуть ссылку и подключить приложение.',
          'Содержимое сайтов и переписки в туннеле мы не читаем. Эти данные не продаём.',
          'На серверах могут оставаться технические записи о сбоях соединения. Это не список сайтов, которые вы открывали.',
          'Если вы пишете боту или на почту, мы видим это сообщение, чтобы отправить ссылку обратно.',
          'Удалить доступ можно письмом на support@k-pax.space с той же почты или сообщением с того же Telegram.',
        ]
      : const [
          'To give you access we store an email or Telegram nick, the account number, the expiry date and the technical key used to connect.',
          'That is enough to create access, return the link and connect the app.',
          'We do not read the sites and messages inside the tunnel. We do not sell this data.',
          'Servers may keep technical notes about failed connections. That is not a list of the sites you opened.',
          'If you write to the bot or by email, we see that message so we can send the link back.',
          'To delete access, write to support@k-pax.space from the same email, or from the same Telegram.',
        ];
  String get support => isRu ? 'Поддержка' : 'Support';
  String get supportSoon => isRu
      ? 'Telegram @k_pax_space и support@k-pax.space'
      : 'Telegram @k_pax_space and support@k-pax.space';
  String get alwaysOnHelpTitle =>
      isRu ? 'Always-on VPN' : 'Always-on VPN';
  String get alwaysOnHelpBody => isRu
      ? 'Откройте Настройки Android → Сеть и интернет → VPN → K-Pax → включите «VPN всегда включён» и при необходимости «Блокировать подключения без VPN».'
      : 'Open Android Settings → Network & internet → VPN → K-Pax → enable “Always-on VPN” and optionally “Block connections without VPN”.';
  String get gotIt => isRu ? 'Понятно' : 'Got it';

  // Subscription / paywall
  String get planName => 'K-Pax';
  String get planExpired => isRu ? 'Истёк' : 'Expired';
  String get subscription => isRu ? 'Подписка' : 'Subscription';
  String get account => isRu ? 'Аккаунт' : 'Account';
  String get manageSubscription =>
      isRu ? 'Управление подпиской' : 'Manage subscription';
  String get choosePlan => isRu ? 'Одна подписка' : 'One subscription';
  String get paywallTitle => isRu
      ? 'Срок подписки закончился'
      : 'Your subscription has ended';
  String get paywallSubtitle => isRu
      ? 'Подписка одна для всех: Германия, Финляндия, Болгария и 2 устройства. Сумма будет одной. Оплата подключится позже.'
      : 'Everyone gets the same subscription: Germany, Finland, Bulgaria and 2 devices. One price. Payment will be connected later.';
  String get trialActiveTitle => isRu ? 'Пробный период' : 'Free trial';
  String daysLeft(int n) => isRu ? 'Осталось $n дн.' : '$n days left';
  String activeUntil(String date) =>
      isRu ? 'Доступ до $date' : 'Access until $date';
  String get paymentStubNote => isRu
      ? 'Демо: реальная оплата ещё не подключена'
      : 'Demo: real payments are not connected yet';
  String get activateDemo => isRu ? 'Активировать демо' : 'Activate demo';
  String get restorePurchases =>
      isRu ? 'Восстановить покупки' : 'Restore purchases';
  String get restoreNothing => isRu
      ? 'Активных покупок не найдено'
      : 'No active purchases found';
  String get restoreOk => isRu ? 'Доступ активен' : 'Access is active';
  String get subscriptionRequired => isRu
      ? 'Нужна активная подписка'
      : 'An active subscription is required';
  String get seePlans => isRu ? 'О подписке' : 'About subscription';
  String get upgrade => isRu ? 'О подписке' : 'About subscription';
  String get referral => isRu ? 'Пригласить друга' : 'Invite a friend';
  String get referralTitle => isRu
      ? 'Подари другу VPN — получи месяц бесплатно'
      : 'Gift a friend VPN — get a free month';
  String get referralBody => isRu
      ? 'Друг получает 14 дней бесплатно. После его первой оплаты вам +30 дней.'
      : 'Your friend gets 14 free days. After their first payment you get +30 days.';
  String get referralProgress => isRu
      ? 'Друзей с оплатой'
      : 'Friends who paid';
  String get referralCap => isRu
      ? 'До 12 бонусных месяцев в год'
      : 'Up to 12 bonus months per year';
  String get copyLink => isRu ? 'Скопировать ссылку' : 'Copy link';
  String get copyCode => isRu ? 'Скопировать код' : 'Copy code';
  String get linkCopied => isRu ? 'Ссылка скопирована' : 'Link copied';
  String get codeCopied => isRu ? 'Код скопирован' : 'Code copied';
  String get simulateReferral => isRu
      ? 'Демо: друг оплатил'
      : 'Demo: friend paid';
  String get referralBonusApplied => isRu
      ? 'Друг оформил подписку. Вам начислен 1 месяц.'
      : 'A friend subscribed. You received 1 free month.';
  String get referralCapReached => isRu
      ? 'Достигнут лимит реферальных месяцев'
      : 'Referral month cap reached';
  String get devices => isRu ? 'Устройства' : 'Devices';
  String get devicesStub => isRu
      ? '1 из 2 (синхронизация позже)'
      : '1 of 2 (sync later)';
  String get userId => isRu ? 'ID пользователя' : 'User ID';
  String get signInStub => isRu
      ? 'Вход по email — скоро'
      : 'Email sign-in — coming soon';
  String get legal => isRu ? 'Документы' : 'Legal';
  String get terms => isRu ? 'Пользовательское соглашение' : 'Terms of use';
  String get termsStub => isRu
      ? 'Срок, страны и устройства'
      : 'Term, countries and devices';
  List<String> get termsParagraphs => isRu
      ? const [
          'K-Pax — личный VPN. Первые 14 дней карта не нужна. Когда срок кончится, доступ остановится, пока не появится оплата.',
          'Подписка одна для всех. Одновременно работают два устройства. Серверы в Германии, Финляндии и Болгарии. Если страну не выбирать, приложение само берёт ту, что отвечает быстрее.',
          'Ссылка показывается один раз и дальше не меняется. Номер счёта сам по себе не подключает. Потерянную ссылку присылает бот с того же Telegram или письмо с той же почты.',
          'Ссылку не передавайте другим людям. Доступ можно остановить, если ей пользуются явно чужие, или если сервер временно недоступен.',
          'Оплата ещё не подключена. Когда она появится, срок продлится по той же ссылке.',
        ]
      : const [
          'K-Pax is a personal VPN. The first 14 days do not need a card. When the term ends, access stops until payment is connected.',
          'Everyone has the same subscription. Two devices can be online at once. Servers are in Germany, Finland and Bulgaria. If you do not pick a country, the app uses the one that answers fastest.',
          'The link is shown once and stays the same. The account number alone does not connect. A lost link comes back from the bot on the same Telegram, or from a message sent from the same email.',
          'Do not give the link to other people. Access can be stopped if strangers are clearly using it, or if a server is temporarily down.',
          'Payment is not connected yet. When it is, the same link is extended.',
        ];
  String get demoTools => isRu ? 'Демо-инструменты' : 'Demo tools';
  String get demoExpire => isRu ? 'Сделать доступ истёкшим' : 'Expire access';
  String get demoResetTrial =>
      isRu ? 'Сбросить trial (14 дней)' : 'Reset trial (14 days)';
  String get purchaseSuccess => isRu
      ? 'Подписка активирована (демо)'
      : 'Subscription activated (demo)';
  String get noAccessYet => isRu
      ? 'Подписки нет. Укажите почту, ник или ссылку выше.'
      : 'No subscription yet. Enter an email, nick or link above.';
  String get emptySubscription => isRu
      ? 'В ссылке нет серверов. Нужна ссылка подписки или vless, vmess, trojan, ss, hy2.'
      : 'The link has no servers. Use a subscription link or vless, vmess, trojan, ss, hy2.';
  String get trialWelcomeTitle => isRu
      ? '14 дней бесплатно'
      : '14 days free';
  String get trialWelcomeBody => isRu
      ? 'Карта не нужна. Подключитесь и оцените K-Pax. Подписка одна для всех.'
      : 'No card required. Connect and try K-Pax. Everyone gets the same subscription.';
  String get continueLabel => isRu ? 'Продолжить' : 'Continue';
  String get sectionPremium => isRu ? 'Подписка' : 'Subscription';
  String get rateApp => isRu ? 'Оценить приложение' : 'Rate the app';
  String get rateAppStub => isRu
      ? 'Ссылка на магазин появится при публикации'
      : 'Store link will appear at release';
  String get shareApp => isRu ? 'Поделиться приложением' : 'Share the app';
  String get diagnostics => isRu ? 'Диагностика' : 'Diagnostics';
  String get diagnosticsHint => isRu
      ? 'Отправить отчёт об ошибке (скоро)'
      : 'Send an error report (soon)';
  String get proLockedHint => isRu
      ? 'Нужна активная подписка'
      : 'An active subscription is required';
}
