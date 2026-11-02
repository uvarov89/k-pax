import 'package:pulse_vpn/core/models/app_settings.dart';
import 'package:pulse_vpn/core/models/connection_models.dart';

class AppStrings {
  const AppStrings(this.lang);

  final AppLanguage lang;

  bool get isRu => lang == AppLanguage.ru;

  String get appName => 'K-Pax';
  String get settings => isRu ? 'Настройки' : 'Settings';
  String get simple => isRu ? 'Простой' : 'Simple';
  String get pro => isRu ? 'Подробно' : 'Details';
  String get connect => isRu ? 'В эфир' : 'Enter orbit';
  String get disconnect => isRu ? 'Покинуть' : 'Leave';
  String get connecting => isRu ? 'Стыковка' : 'Docking';
  String get disconnecting => isRu ? 'Сход' : 'Leaving';
  String get retry => isRu ? 'Ещё раз' : 'Try again';
  String get notConnected => isRu ? 'Вне эфира' : 'Off the air';
  String get connectingStatus => isRu ? 'Стыковка…' : 'Docking…';
  String get reconnectingStatus =>
      isRu ? 'Возврат на орбиту…' : 'Returning to orbit…';
  String get reconnectFailed => isRu
      ? 'Не удалось вернуться. Нажмите «В эфир».'
      : 'Could not return. Tap Enter orbit.';
  String get disconnectingStatus => isRu ? 'Сход с орбиты…' : 'Leaving orbit…';
  String get connectionError =>
      isRu ? 'Стыковка не вышла' : 'Docking failed';
  String get connectFailed =>
      isRu ? 'Не удалось выйти в эфир' : 'Could not enter orbit';
  String get killSwitchHeld => isRu
      ? 'Связь оборвалась. Трафик закрыт, пока снова не выйдете в эфир.'
      : 'The link dropped. Traffic stays blocked until you enter orbit again.';
  String get loginConfirmedFlash => isRu
      ? 'Вход подтверждён — доступ обновлён'
      : 'Sign-in confirmed — access refreshed';
  String get updateDownloading =>
      isRu ? 'Обновляем K-Pax…' : 'Updating K-Pax…';
  String connectedTo(String place) =>
      isRu ? 'На орбите · $place' : 'In orbit · $place';
  String get connectedTagline =>
      isRu ? 'Чистый эфир' : 'Clear airwaves';
  String get onboardingTitle => 'Planet K-Pax';
  String get onboardingBody => isRu
      ? 'Интернет без лишнего шума. 14 дней бесплатно, без карты. Одна ссылка на телефон и компьютер.'
      : 'Internet with less noise. 14 days free, no card. One link for phone and computer.';
  String get onboardingCta => isRu ? 'Начать' : 'Begin';
  String get auto => isRu ? 'Автовыбор' : 'Auto';
  String get country => isRu ? 'Страна' : 'Country';
  String get bestServerAuto => isRu
      ? 'Сам выбирает сервер и тип подключения'
      : 'Picks the server and the connection type';
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
  String protocolLabel(TunnelProtocol protocol) => switch (protocol) {
        TunnelProtocol.auto => isRu ? 'Авто' : 'Auto',
        TunnelProtocol.hysteria2 => 'Hysteria2',
        TunnelProtocol.vlessReality => 'VLESS',
        TunnelProtocol.grpc => isRu ? 'Запасной' : 'Backup',
        TunnelProtocol.tuic => 'TUIC',
        TunnelProtocol.message => isRu ? 'Сообщения' : 'Messages',
      };
  String bypassLabel(BypassMode mode) => switch (mode) {
        BypassMode.auto => isRu ? 'Авто' : 'Auto',
        BypassMode.tcpOnly => isRu ? 'Только TCP' : 'TCP only',
        BypassMode.udpPrefer => isRu ? 'Сначала UDP' : 'UDP first',
      };
  String bypassHint(BypassMode mode) => switch (mode) {
        BypassMode.auto => isRu
            ? 'Сначала Hysteria2, затем VLESS, запасной и TUIC. «Сообщения» — если остальное не ответило.'
            : 'Hysteria2 first, then VLESS, backup and TUIC. Messages only if the rest do not answer.',
        BypassMode.tcpOnly => isRu
            ? 'Только TCP: VLESS, запасной и «сообщения». Hysteria2 и TUIC не используются.'
            : 'TCP only: VLESS, backup and messages. Hysteria2 and TUIC stay unused.',
        BypassMode.udpPrefer => isRu
            ? 'Сначала Hysteria2 и TUIC. Если они молчат, пробуются TCP-профили.'
            : 'Hysteria2 and TUIC first. TCP profiles are tried if those stay silent.',
      };
  String get dns => 'DNS';
  String get dnsThroughTunnel =>
      isRu ? 'DNS через туннель' : 'DNS through the tunnel';
  String get dnsComputer =>
      isRu ? 'DNS компьютера' : 'The computer DNS';
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
  String get splitAddProgram =>
      isRu ? 'Добавить программу' : 'Add a program';
  String get splitWindowsNote => isRu
      ? 'Имя файла, например chrome.exe. Применится при следующем подключении.'
      : 'A file name, for example chrome.exe. It applies on the next connection.';
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
  String get testNodes => isRu ? 'Проверить серверы' : 'Check servers';
  String get testingNodes => isRu ? 'Проверка…' : 'Checking…';
  String get probeEmpty => isRu
      ? 'Сначала сохраните ссылку в аккаунте. Проверяются серверы из неё.'
      : 'Save the link in the account first. The check uses servers from that link.';
  String get probeNoAnswer => isRu ? 'нет ответа' : 'no answer';
  String get ipv6 => 'IPv6';
  String get protocolFallback =>
      isRu ? 'Fallback протоколов' : 'Protocol fallback';
  String get protocolFallbackHint => isRu
      ? 'Если выбранный тип не отвечает, пробуются остальные, строка «сообщения» — в конце'
      : 'If the chosen type does not answer, the others are tried. The message line is last.';
  String get reconnect => isRu ? 'Переподключение' : 'Reconnect';
  String get sectionConnection => isRu ? 'Подключение' : 'Connection';
  String get sectionNotifications => isRu ? 'Уведомления' : 'Notifications';
  String get sectionAccount => isRu ? 'Аккаунт' : 'Account';
  String get sectionAppearance => isRu ? 'Внешний вид' : 'Appearance';
  String get sectionAbout => 'About K-Pax';
  String get autoConnectLaunch =>
      isRu ? 'Автоподключение при запуске' : 'Connect on launch';
  String get launchWithWindows =>
      isRu ? 'Запускать вместе с Windows' : 'Start with Windows';
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
  String get refreshSubscriptionNotice => isRu
      ? 'Мы обновили серверы для стабильности. Нажмите «Обновить», чтобы подтянуть новые настройки.'
      : 'We updated servers for stability. Tap Refresh to pull the new settings.';
  String get refreshSubscriptionAction => isRu ? 'Обновить' : 'Refresh';
  String get dismissNotice => isRu ? 'Скрыть' : 'Dismiss';
  String get pasteLinkTitle => isRu ? 'Войти или вставить ссылку' : 'Sign in or paste a link';
  String get pasteLinkBody => isRu
      ? 'Почта или @ник Telegram — придёт подтверждение, ссылка подгрузится сама. Можно вставить ссылку K-Pax или подписку другого провайдера — вход не нужен.'
      : 'Email or @Telegram nick — confirm ownership, then the link loads itself. Or paste a K-Pax / other-provider subscription link — no sign-in needed.';
  String get pasteLinkHint => isRu
      ? 'Почта, @ник, https://sub.k-pax.space/s/… или ссылка другого провайдера'
      : 'Email, @nick, https://sub.k-pax.space/s/… or another provider link';
  String get saveLink => isRu ? 'Продолжить' : 'Continue';
  String get loginWithContact => isRu ? 'Войти' : 'Sign in';
  String get pasteOwnLink => isRu ? 'Вставить свою ссылку' : 'Paste your link';
  String get openBotConfirm => isRu ? 'Открыть бота' : 'Open the bot';
  String get waitingEmailConfirm => isRu
      ? 'Письмо отправлено. Нажмите кнопку в письме — доступ появится здесь сам, ссылку копировать не нужно.'
      : 'Email sent. Tap the button in the message — access appears here; no need to copy a link.';
  String get waitingTelegramConfirm => isRu
      ? 'Откройте бота и нажмите «Подтвердить» — доступ появится здесь сам.'
      : 'Open the bot and tap Confirm — access appears here.';
  String get cancelLogin => isRu ? 'Отменить' : 'Cancel';
  String get loginTimedOut => isRu
      ? 'Время подтверждения вышло. Запросите вход ещё раз.'
      : 'Confirmation timed out. Start sign-in again.';
  String get openProfileForAccess => isRu
      ? 'Войдите почтой или @ником в профиле'
      : 'Sign in with email or @nick in the profile';
  String get linkReadyTitle => isRu ? 'Доступ включён' : 'Access is on';
  String get linkReadyBody => isRu
      ? 'Ссылка сохранена в приложении. Скопируйте её для компьютера: второй раз мы её не покажем.'
      : 'The link is saved in the app. Copy it for your computer: it will not be shown again.';
  String get badLink => isRu
      ? 'Не похоже на почту, @ник или ссылку подписки.'
      : 'Does not look like an email, @nick, or subscription link.';
  String get linkOpenFailed => isRu
      ? 'Ссылка не открылась. Проверьте интернет и попробуйте ещё раз.'
      : 'The link did not open. Check the internet and try again.';
  String get replaceLink => isRu ? 'Заменить ссылку' : 'Replace link';
  String get serversUpdated =>
      isRu ? 'Серверы обновлены' : 'Servers updated';
  String get language => isRu ? 'Язык' : 'Language';
  String get theme => isRu ? 'Тема' : 'Theme';
  String get themeDark => isRu ? 'Тёмная' : 'Dark';
  String get themeLight => isRu ? 'Светлая' : 'Light';
  String get about => 'About K-Pax';
  String get aboutPlanet => 'Planet K-Pax';
  String get aboutLead => isRu
      ? 'K-Pax создаёт спокойное соединение между вашим устройством и сетью. Без лишнего шума и без автопродления.'
      : 'K-Pax makes a calm link between your device and the network. Less noise, and no auto-renewal.';
  String get aboutThesisQuietTitle =>
      isRu ? 'Чистый эфир' : 'Clear airwaves';
  String get aboutThesisQuietBody => isRu
      ? 'Рекламные сети и счётчики отключаются на подключении. Меньше шума в ленте и на сайтах.'
      : 'Ad networks and trackers drop on connect. Less noise in feeds and on sites.';
  String get aboutThesisLinkTitle =>
      isRu ? 'Одна ссылка' : 'One link';
  String get aboutThesisLinkBody => isRu
      ? 'Телефон и компьютер на одной ссылке. Два устройства сразу, сверху — автоматический выбор сервера.'
      : 'Phone and computer share one link. Two devices at once, with automatic server pick on top.';
  String get aboutThesisPayTitle =>
      isRu ? 'Без автопродления' : 'No auto-renewal';
  String get aboutThesisPayBody => isRu
      ? 'Карту не привязываем. Понравится — разово 110 ₽ через СБП. Не понравится — просто не продлеваете.'
      : 'No card on file. Like it — pay 110 ₽ once via SBP. If not — just do not renew.';
  String get aboutChangelogTitle => isRu ? 'Что нового' : 'What is new';
  List<String> get aboutChangelog => isRu
      ? const [
          'Обновление серверов и стабильности — обновите подписку в приложении, если трафик оборвался.',
          'Список устройств и отключение лишнего с телефона или компьютера.',
          'Автообновление Android и Windows: установка из приложения (APK / Setup).',
          'Фон космоса, экран «О КаПэкс», статусы эфира и онбординг — на телефоне и на ПК.',
        ]
      : const [
          'Server and stability update — refresh the subscription in the app if traffic dropped.',
          'Device list and the option to kick an extra session from phone or computer.',
          'Android and Windows auto-update: install from the app (APK / Setup).',
          'Space backdrop, About K-Pax, orbit statuses and onboarding — on phone and PC.',
        ];
  String get aboutOpenSite => isRu ? 'Сайт k-pax.space' : 'Site k-pax.space';
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
  String updateTitle(String version) => isRu
      ? 'Доступна версия $version'
      : 'Version $version is available';
  String get updateBody => isRu
      ? 'K-Pax обновится сам и откроется снова. Подключение на это время прервётся, ссылка подписки останется той же.'
      : 'K-Pax will update itself and open again. The connection pauses for that, and the subscription link stays the same.';
  String get updateNow => isRu ? 'Обновить' : 'Update';
  String get updateLater => isRu ? 'Позже' : 'Later';
  String get checkUpdates => isRu ? 'Проверить обновления' : 'Check for updates';
  String get updateCurrent =>
      isRu ? 'Установлена последняя версия' : 'You have the latest version';
  String get updateCheckFailed => isRu
      ? 'Не удалось проверить обновление. Проверьте интернет и повторите.'
      : 'Could not check for an update. Check the internet and try again.';
  String get updateApplyFailed => isRu
      ? 'Не удалось обновить K-Pax. Проверьте интернет и повторите.'
      : 'Could not update K-Pax. Check the internet and try again.';
  String get updateInstallPermission => isRu
      ? 'Разрешите установку из K-Pax в настройках Android и повторите обновление.'
      : 'Allow installs from K-Pax in Android settings, then try the update again.';
  String get quitApp => isRu ? 'Закрыть приложение' : 'Quit the app';
  String get quitAppHint => isRu
      ? 'Крестик убирает окно в трей. Эта кнопка завершает программу.'
      : 'The close button hides the window in the tray. This quits the app.';
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
      ? 'Подписка одна: 110 ₽ за 30 дней и 2 устройства. Оплата продлевает ту же ссылку.'
      : 'One subscription: 110 ₽ for 30 days and 2 devices. Payment extends the same link.';
  String get trialActiveTitle => isRu ? 'Пробный период' : 'Free trial';
  String daysLeft(int n) => isRu ? 'Осталось $n дн.' : '$n days left';
  String activeUntil(String date) =>
      isRu ? 'Доступ до $date' : 'Access until $date';
  String get paymentNote => isRu
      ? '110 ₽ за 30 дней, разовая оплата через СБП на сайте. Без автопродления. Оплата продлевает ту же ссылку.'
      : '110 ₽ for 30 days, a one-time SBP payment on the site. No auto-renewal. Payment extends the same link.';
  String get buyOnSite => isRu ? 'Открыть оплату' : 'Open payment';
  String get subscriptionRequired => isRu
      ? 'Нужна активная подписка'
      : 'An active subscription is required';
  String get seePlans => isRu ? 'О подписке' : 'About subscription';
  String get upgrade => isRu ? 'О подписке' : 'About subscription';
  String get referral => isRu ? 'Пригласить друга' : 'Invite a friend';
  String get referralTitle => isRu ? '15 дней за друга' : '15 days for a friend';
  String get referralBody => isRu
      ? 'Отправьте ссылку. Когда человек впервые получит доступ, к вашей подписке добавится 15 дней. Ему откроются обычные 14.'
      : 'Send the link. When someone gets access for the first time, you receive 15 days. They get the usual 14.';
  String inviteLink(String id) => 'https://k-pax.space/?ref=$id';
  String get referralProgress => isRu
      ? 'Приглашённых'
      : 'People invited';
  String get referralCap => isRu
      ? 'Дни добавляются к той же ссылке'
      : 'Days are added to the same link';
  String get copyLink => isRu ? 'Скопировать ссылку' : 'Copy link';
  String get copyCode => isRu ? 'Скопировать код' : 'Copy code';
  String get linkCopied => isRu ? 'Ссылка скопирована' : 'Link copied';
  String get codeCopied => isRu ? 'Код скопирован' : 'Code copied';
  String get devices => isRu ? 'Устройства' : 'Devices';
  String get devicesHint => isRu
      ? 'До 2 устройств одновременно. Третье отключится само.'
      : 'Up to 2 devices at once. A third one is disconnected.';
  String get devicesEmpty => isRu
      ? 'Сейчас онлайн нет других устройств'
      : 'No other devices online now';
  String get devicesLoadFailed => isRu
      ? 'Не удалось загрузить список устройств'
      : 'Could not load the device list';
  String get devicesKick => isRu ? 'Отключить' : 'Disconnect';
  String get devicesKicked => isRu
      ? 'Устройство будет отключено в течение минуты'
      : 'The device will disconnect within a minute';
  String get devicesRefresh => isRu ? 'Обновить список' : 'Refresh list';
  String get refreshAccess => isRu ? 'Обновить доступ' : 'Refresh access';
  String get refreshAccessHint => isRu
      ? 'Уже оплатили на сайте — подтянуть срок без повторного входа'
      : 'Already paid on the site — refresh access without signing in again';
  String get paidRefreshDone => isRu
      ? 'Доступ обновлён'
      : 'Access refreshed';
  String get loginWaitingHome => isRu
      ? 'Ждём подтверждение входа…'
      : 'Waiting for sign-in confirmation…';
  String get lostAccessHelp => isRu
      ? 'Потеряли доступ — введите ту же почту или @ник выше: для почты придёт письмо, для Telegram откроется бот.'
      : 'Lost access — enter the same email or @nick above: email gets a letter, Telegram opens the bot.';
  String get userId => isRu ? 'ID пользователя' : 'User ID';
  String get legal => isRu ? 'Документы' : 'Legal';
  String get terms => isRu ? 'Пользовательское соглашение' : 'Terms of use';
  List<String> get termsParagraphs => isRu
      ? const [
          'K-Pax — личный VPN. Первые 14 дней карта не нужна. Когда срок кончится, доступ остановится, пока не появится оплата.',
          'Подписка одна для всех. Одновременно работают два устройства. Если страну не выбирать, приложение само берёт ту, что отвечает быстрее.',
          'Ссылка показывается один раз и дальше не меняется. Номер счёта сам по себе не подключает. Потерянную ссылку присылает бот с того же Telegram или письмо с той же почты.',
          'Ссылку не передавайте другим людям. Доступ можно остановить, если ей пользуются явно чужие, или если сервер временно недоступен.',
          '110 ₽ продлевают ту же ссылку на 30 дней. Оплата не создаёт новую ссылку и не продлевается сама.',
        ]
      : const [
          'K-Pax is a personal VPN. The first 14 days do not need a card. After that a subscription is 110 ₽ for 30 days. When the term ends, access stops until it is extended.',
          'Everyone has the same subscription. Two devices can be online at once. If you do not pick a country, the app uses the one that answers fastest.',
          'The link is shown once and stays the same. The account number alone does not connect. A lost link comes back from the bot on the same Telegram, or from a message sent from the same email.',
          'Do not give the link to other people. Access can be stopped if strangers are clearly using it, or if a server is temporarily down.',
          '110 ₽ extends the same link by 30 days. Payment does not create a new link.',
        ];
  String get noAccessYet => isRu
      ? 'Подписки нет. Укажите почту, ник или ссылку выше.'
      : 'No subscription yet. Enter an email, nick or link above.';
  String get emptySubscription => isRu
      ? 'В ссылке нет подходящих серверов. Подходят подписки списком, Clash или JSON и ссылки vless, vmess, trojan, ss, hy2, tuic.'
      : 'The link has no usable servers. Subscriptions as a list, Clash or JSON work, and vless, vmess, trojan, ss, hy2, tuic links.';
  String get ownServer => isRu ? 'Свой сервер' : 'Own server';
  String get mySubscriptions => isRu ? 'Мои подписки' : 'My subscriptions';
  String get mySubscriptionsHint => isRu
      ? 'Нажмите на подписку, чтобы подключаться через неё. Новую ссылку вставьте в поле выше.'
      : 'Tap a subscription to connect through it. Paste a new link in the field above.';
  String get activeSubscription => isRu ? 'Сейчас используется' : 'In use';
  String get removeSubscription => isRu ? 'Удалить подписку' : 'Remove subscription';
  String removeSubscriptionBody(String name) => isRu
      ? '«$name» исчезнет из приложения. У провайдера подписка останется, ссылку можно добавить снова.'
      : '"$name" will be removed from the app. The provider keeps it, and the link can be added again.';
  String get remove => isRu ? 'Удалить' : 'Remove';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get noExpiry => isRu ? 'Без срока' : 'No end date';
  String get providerExpired => isRu
      ? 'Срок подписки у провайдера закончился. Продлите её у него или выберите другую подписку в профиле.'
      : 'The provider subscription has ended. Renew it there or pick another subscription in the profile.';
  String get providerSite => isRu ? 'Сайт провайдера' : 'Provider site';
  String get providerSiteHint => isRu
      ? 'Продление и вопросы по этой подписке'
      : 'Renewal and questions about this subscription';
  String get continueLabel => isRu ? 'Продолжить' : 'Continue';
  String get sectionPremium => isRu ? 'Подписка' : 'Subscription';
  String get proLockedHint => isRu
      ? 'Нужна активная подписка'
      : 'An active subscription is required';
}
