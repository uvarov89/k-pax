"""XPLM neon website. HTML only; panel.py owns validation and all actions."""

ASSET_VERSION = "20261106-neon1"


def icon(name: str) -> str:
    paths = {
        "arrow": '<path d="M4 12h16m-6-6 6 6-6 6"/>',
        "shield": '<path d="m12 2 9 4v6c0 5-5 9-9 11C8 21 3 17 3 12V6Z"/><path d="m8 12 3 3 5-6"/>',
        "globe": '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M5 6h14M5 18h14"/>',
        "devices": '<rect x="2" y="3" width="15" height="12" rx="2"/><path d="M6 20h7m-3-5v5"/><rect x="16" y="9" width="6" height="12" rx="1"/>',
        "bolt": '<path d="m14 2-9 12h7l-2 8 9-12h-7Z"/>',
        "infinity": '<path d="M12 12C7 3 1 7 2 12s5 8 10 0 11-5 10 0-6 9-10 0Z"/>',
        "block": '<circle cx="12" cy="12" r="9"/><path d="m6 6 12 12M7 17 17 7"/>',
        "download": '<path d="M12 2v13m-5-5 5 5 5-5M3 15v6h18v-6"/>',
        "mail": '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m3 6 9 7 9-7"/>',
        "gift": '<path d="M3 11h18v10H3zM2 7h20v4H2zM12 7v14"/><path d="M12 7C3 8 4-1 9 3Zm0 0c9 1 8-8 3-4Z"/>',
        "rocket": '<path d="M8 16c-1-6 5-13 13-13 0 8-7 14-13 13Z"/><circle cx="15" cy="8" r="2"/><path d="m8 9-5 1-1 5 5-1m8 2-1 5-5 1 1-5M3 21l3-3"/>',
    }
    return '<svg class="xp-icon" viewBox="0 0 24 24" aria-hidden="true">' + paths[name] + '</svg>'


def mark() -> str:
    return '<img src="/assets/xplm-mark.svg?v=' + ASSET_VERSION + '" width="56" height="64" alt=""><span class="xp-wordmark"><b>XPLM</b><small>БЕЗ РЕКЛАМЫ</small></span>'


def header(*, home: bool = False, wide: bool = False) -> str:
    if wide:
        return '<header class="xp-header xp-admin-header"><a class="xp-logo" href="/" aria-label="XPLM, на главную">' + mark() + '</a><a class="xp-outline" href="/">На сайт</a></header>'
    return '<header class="xp-header"><a class="xp-logo" href="/" aria-label="XPLM, на главную">' + mark() + '</a><nav aria-label="Главное меню"><a href="/#features">Возможности</a><a href="/#connect">Как подключить</a><a href="/#price">Тариф</a><a href="/faq">FAQ</a></nav><a class="xp-account xp-outline" href="/#start">Моё подключение</a></header>'


def checks(items: tuple[str, ...]) -> str:
    return '<ul class="xp-checks">' + ''.join('<li>' + item + '</li>' for item in items) + '</ul>'


def footer() -> str:
    return '<footer class="xp-footer"><a class="xp-logo" href="/" aria-label="XPLM, на главную">' + mark() + '</a><nav aria-label="Ссылки в подвале"><a href="/#features">Возможности</a><a href="/#price">Тариф</a><a href="/faq">FAQ</a><a href="mailto:support@x-plm.online">Поддержка</a></nav><p>XPLM — интернет без рекламы и помех.</p><div class="xp-legal-links"><a href="/terms">Соглашение</a><a href="/privacy">Конфиденциальность</a><a href="/terms#refund">Возврат</a><a href="/status">Статус сервиса</a></div></footer>'


HOME = '''
<section class="xp-hero" aria-labelledby="hero-title">
<img class="xp-hero-art" src="/assets/xplm-hero.webp?v=20261106-neon1" width="1536" height="1024" alt="" fetchpriority="high">
<div class="xp-hero-copy">
<p class="xp-hero-brand">XPLM</p>
<h1 id="hero-title">Интернет<br><em>без рекламы</em><br>и помех</h1>
<p class="xp-sub">Блокировка рекламы и трекеров.<br>Защищённое соединение на телефоне и компьютере.</p>
<div class="xp-trial">''' + icon("gift") + '''<span><b>14 дней бесплатно</b><small>Без привязки карты</small></span></div>
<a class="xp-primary" href="#start">Попробовать бесплатно ''' + icon("arrow") + '''</a>
</div>
</section>
<section class="xp-feature-strip" aria-label="Возможности сервиса">
<div>''' + icon("infinity") + '''<span>Безлимитный<br>трафик</span></div>
<div>''' + icon("bolt") + '''<span>Высокая<br>скорость</span></div>
<div>''' + icon("shield") + '''<span>Защищённое<br>соединение</span></div>
<div>''' + icon("block") + '''<span>Блокировка<br>рекламы и трекеров</span></div>
</section>
<section class="xp-benefits-section" id="features" aria-labelledby="benefits-title">
<div class="xp-benefits-copy"><h2 id="benefits-title">Почему <br>выбирают <br><em>XPLM?</em></h2><p>Защищённое соединение без рекламы и помех на всех ваших устройствах.</p></div>
<div class="xp-benefits-grid">
<article>''' + icon("globe") + '''<p>Серверы в Германии, Финляндии и Болгарии</p></article>
<article>''' + icon("devices") + '''<p>Одна подписка для двух устройств одновременно</p></article>
<article>''' + icon("shield") + '''<p>Защищённое соединение и защита данных</p></article>
<article>''' + icon("rocket") + '''<p>Простое и быстрое подключение</p></article>
</div>
<div class="xp-devices-visual"><img class="xp-devices-art" src="/assets/xplm-devices.webp?v=20261106-neon1" width="1536" height="1024" alt="XPLM на ноутбуке и телефоне" loading="lazy"></div>
</section>
<section class="xp-price-strip" id="price" aria-label="Тариф XPLM">
<div><h2>Один тариф.<br>Никаких сюрпризов.</h2><p>Разовая оплата. Без автопродления.</p></div>
<div class="xp-price"><span class="xp-green-badge">14 дней бесплатно</span><p><b>299 ₽</b><span>/ 30 дней</span></p></div>
''' + checks(("Безлимитный трафик", "Два устройства", "Серверы в трёх странах", "Блокировка рекламы")) + '''
<a class="xp-primary" href="#start">Начать бесплатно ''' + icon("arrow") + '''</a>
</section>
<section class="xp-connect" id="connect" aria-labelledby="connect-title">
<div><h2 id="connect-title">Как подключить <br><em>XPLM?</em></h2><p>Всего 3 простых шага:</p></div>
<ol>
<li><span class="xp-step-number">1</span>''' + icon("download") + '''<a href="#apps">Установите <br>приложение</a></li>
<li><span class="xp-step-number">2</span>''' + icon("mail") + '''<a href="#start">Получите ссылку <br>на подключение</a></li>
<li><span class="xp-step-number">3</span>''' + icon("shield") + '''<span>Включите защиту <br>и блокировку рекламы</span></li>
</ol>
</section>
<section class="xp-banners" aria-label="Помощь с подключением">
<article class="xp-lifestyle"><img src="/assets/xplm-lifestyle.webp?v=20261106-neon1" width="1536" height="1024" alt="Девушка слушает музыку в наушниках" loading="lazy"><div><h2>Интернет<br><em>без помех</em></h2><p>Смотрите, общайтесь и работайте. XPLM помогает убрать рекламу и защитить соединение.</p></div></article>
<article class="xp-faq-banner"><div><h2>Остались вопросы?</h2><p>Ответы на частые вопросы<br>в нашем разделе FAQ</p><a class="xp-outline" href="/faq">Перейти к FAQ ''' + icon("arrow") + '''</a></div><span class="xp-chat-art" aria-hidden="true"><i></i><i></i><i></i></span></article>
</section>
<section class="xp-access" id="start" aria-labelledby="access-title">
<div class="xp-access-copy"><p class="xp-eyebrow">ВАШЕ ПОДКЛЮЧЕНИЕ</p><h2 id="access-title">Начните с 14 дней <br><em>без рекламы</em></h2><p>Укажите почту. После подтверждения получите личную ссылку для двух устройств.</p><p class="muted">Уже подключались? Введите ту же почту. Если ссылка потерялась, здесь можно получить её повторно.</p><a class="xp-outline" href="/pay">Продлить за 299 ₽ ''' + icon("arrow") + '''</a></div>
<form class="signup xp-signup" method="post" action="/signup">
<label for="contact">Ваша почта</label>
<input id="contact" name="contact" type="email" autocomplete="email" required maxlength="80" placeholder="name@mail.ru" value="{contact}">
<div class="hp" aria-hidden="true"><input name="company" tabindex="-1" autocomplete="off"></div>
{captcha_fields}{ref_field}{ref_note}{note}{action}{err}{submit}{legal}
</form>
</section>
<section class="xp-app-section" id="apps" aria-labelledby="apps-title">
<h2 id="apps-title">Приложение для ваших устройств</h2><p>{apps_hint}</p>
<div class="xp-apps">
<a class="xp-outline" href="{android_url}">XPLM · Android ''' + icon("download") + '''</a>
<a class="xp-outline" href="https://apps.apple.com/app/incy/id6756943388" target="_blank" rel="noopener">INCY · iPhone</a>
<a class="xp-outline" href="https://apps.apple.com/app/happ-proxy-utility/id6504287215" target="_blank" rel="noopener">Happ · iPhone</a>
<a class="xp-outline" href="https://play.google.com/store/apps/details?id=llc.itdev.incy" target="_blank" rel="noopener">INCY · Android</a>
<a class="xp-outline" href="https://play.google.com/store/apps/details?id=com.happproxy" target="_blank" rel="noopener">Happ · Android</a>
<a class="xp-outline" href="{windows_url}">X-Plm · Windows ''' + icon("download") + '''</a>
</div><p class="muted">В приложении X-Plm войдите по почте. В INCY или Happ нажмите «+» и вставьте полученную ссылку, затем выберите автоматический сервер.</p>
</section>
<section class="xp-extras" aria-label="Дополнительные возможности">
<article><h2>Поделитесь с другом</h2><p>За нового пользователя по вашей ссылке получите 15 дней. Каждая шестая оплата добавляет ещё 7 дней к сроку.</p><div class="xp-inline-actions"><button type="button" class="ghost" id="open-ref">Получить приглашение</button><button type="button" class="ghost" id="open-gift">Оплатить другу</button></div></article>
<article class="promostrip xp-promo" id="promo"><h2>Есть промокод?</h2>{promo_note}{promo_err}
<form method="post" action="/promo"><div class="promorow"><div><label for="promo-contact">Почта</label><input id="promo-contact" name="contact" type="email" autocomplete="email" required maxlength="80" placeholder="name@mail.ru" value="{promo_contact}"></div><div><label for="promo-code">Промокод</label><input id="promo-code" name="code" required maxlength="32" placeholder="КОД" value="{promo_code}" autocomplete="off"></div><button type="submit">Применить</button></div><div class="hp" aria-hidden="true"><input name="company" tabindex="-1" autocomplete="off"></div></form></article>
</section>
<section class="xp-questions" id="faq"><h2>Частые вопросы</h2><div class="xp-faq">
<details><summary>Нужно ли привязывать карту?</summary><p>Нет. Первые 14 дней бесплатно, только по почте. Ничего не спишется автоматически.</p></details>
<details><summary>Как продлить подключение?</summary><p>На странице <a href="/pay">оплаты</a>: 299 ₽ за 30 дней через СБП. Разовая оплата, без автопродления. Ссылка остаётся прежней.</p></details>
<details><summary>Сколько устройств можно подключить?</summary><p>Два одновременно. Например, телефон и компьютер, с одной ссылкой.</p></details>
<details><summary>Что делать, если ссылка потерялась?</summary><p>Введите ту же почту в <a href="#start">форме подключения</a>. Или напишите с этой почты на <a href="mailto:access@x-plm.online">access@x-plm.online</a>, робот пришлёт её повторно.</p></details>
</div><a href="/faq">Все вопросы и ответы →</a></section>
''' + footer() + '''
<script src="/assets/xplm-site.js?v=20261106-neon1" defer></script>
'''
