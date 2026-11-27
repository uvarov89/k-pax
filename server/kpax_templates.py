"""K-Pax home — same Light tool structure as X-Plm, dark cosmos theme. Sky/KALEID untouched."""

ICON_ARROW = (
    '<svg class="kp-ic" viewBox="0 0 24 24" aria-hidden="true">'
    '<path d="M5 12h14M13 6l6 6-6 6"/></svg>'
)

BENEFITS = (
    ("Тише в ленте", "Рекламные сети и счётчики отключаются на подключении."),
    ("Одна ссылка", "Телефон и компьютер. Сверху — автоматический выбор сервера."),
    ("Разово 110 ₽", "Карту не привязываем. Не понравится — просто не продлеваете."),
    ("Живая поддержка", "Пишите на support@k-pax.space или в Telegram бота."),
)


def benefits_html() -> str:
    return "".join(
        '<article class="kp-benefit"><h3>%s</h3><p>%s</p></article>' % (t, p)
        for t, p in BENEFITS
    )


def check_list(items: tuple[str, ...]) -> str:
    return '<ul class="kp-checks">%s</ul>' % "".join(
        "<li><span>%s</span></li>" % item for item in items
    )


HOME = (
    """
<section class="kp-hero">
<div class="kp-hero-copy">
<p class="kp-eyebrow">14 дней · без карты</p>
<h1 class="kp-title">Интернет без рекламы</h1>
<p class="kp-sub">Одна ссылка на телефон и компьютер. Разовая оплата 110 ₽, без автопродления.</p>
<div class="kp-actions">
<a class="restore kp-primary" href="#start">Получить ссылку """
    + ICON_ARROW
    + """</a>
<a class="kp-secondary" href="#price">Тариф 110 ₽</a>
</div>
<div class="kp-facts" aria-label="Коротко о тарифе">
<div><b>14 дней</b><span>бесплатно, без карты</span></div>
<div><b>2 устройства</b><span>одна ссылка на оба</span></div>
<div><b>110 ₽</b><span>за 30 дней, разово</span></div>
</div>
</div>
<div class="kp-hero-art" aria-hidden="true">
<figure class="kp-phone" aria-label="Главный экран K-Pax">
<div class="kp-phone-bezel">
<div class="kp-phone-notch"></div>
<div class="kp-phone-screen">
<header class="kp-app-top">
<span class="kp-app-mark">K-Pax</span>
<span class="kp-app-pill kp-app-pill-idle"><i></i>Автовыбор</span>
</header>
<div class="kp-app-main">
<p class="kp-app-status kp-app-status-idle">Вне эфира</p>
<div class="kp-app-orb" role="presentation">
<span class="kp-app-orb-ring"></span>
<span class="kp-app-orb-core">В эфир</span>
</div>
</div>
<div class="kp-app-loc">
<span class="kp-app-loc-label">Локация</span>
<span class="kp-app-loc-value">Автовыбор</span>
<span class="kp-app-loc-hint">Сам выбирает сервер и тип подключения</span>
</div>
</div>
</div>
</figure>
</div>
</section>

<section class="kp-section">
<h2 class="kp-h2">Что вы получаете</h2>
<p class="kp-lead">Спокойная сеть без всплывающей рекламы и слежки — дома, в кафе и в поездках.</p>
<div class="kp-benefits">"""
    + benefits_html()
    + """</div>
</section>

<section class="kp-section" id="start">
<h2 class="kp-h2">Как начать</h2>
<p class="kp-lead">Три шага, около двух минут. Первые 14 дней — бесплатно.</p>
<ol class="kp-steps">
<li class="kp-step">
<span class="kp-num">1</span>
<h3>Установите приложение</h3>
<p>{apps_hint}</p>
<div class="kp-apps">
<a href="{windows_url}" rel="noopener">K-Pax · Windows</a>
<a href="{android_url}" rel="noopener">K-Pax · Android</a>
<a href="https://apps.apple.com/app/incy/id6756943388" target="_blank" rel="noopener">INCY · iPhone</a>
<a href="https://apps.apple.com/app/happ-proxy-utility/id6504287215" target="_blank" rel="noopener">Happ · iPhone</a>
</div>
</li>
<li class="kp-step kp-step-main">
<span class="kp-num">2</span>
<h3>Зарегистрируйтесь</h3>
<p>Укажите почту. Код придёт письмом — введите его в приложении K-Pax. На сайте после подтверждения также покажем ссылку подписки (для письма и редких случаев).</p>
<form class="signup" method="post" action="/signup">
<label for="contact">Почта</label>
<input id="contact" name="contact" type="email" autocomplete="email" required maxlength="80" placeholder="name@mail.ru" value="{contact}">
<div class="hp" aria-hidden="true"><input name="company" tabindex="-1" autocomplete="off"></div>
{captcha_fields}
{ref_field}
{ref_note}
{note}
{action}
{err}
{submit}
{legal}
</form>
</li>
<li class="kp-step">
<span class="kp-num">3</span>
<h3>Подключитесь в приложении</h3>
<p>В K-Pax для Windows или Android: почта → код из письма → готово. Ссылку копировать не нужно.</p>
<p class="muted">На iPhone пока откройте INCY или Happ и вставьте ссылку с сайта или из письма. Если почта уже есть, ссылку повторно на сайте не показываем — вернём письмом на access@k-pax.space.</p>
</li>
</ol>
</section>

<section class="kp-section" id="price">
<h2 class="kp-h2">Тариф</h2>
<p class="kp-lead">Сначала 14 дней бесплатно. Понравится — продлите на месяц одной оплатой.</p>
<div class="kp-plans">
<article class="kp-plan">
<p class="kp-plan-name">Пробный период</p>
<p class="kp-plan-price"><b>0 ₽</b><span>14 дней</span></p>
"""
    + check_list(("Всё, что в подписке", "Без привязки карты", "Ничего не спишется само"))
    + """
<a class="kp-secondary kp-wide" href="#start">Начать бесплатно</a>
</article>
<article class="kp-plan kp-plan-main">
<p class="kp-plan-tag">Основной</p>
<p class="kp-plan-name">Подписка на 30 дней</p>
<p class="kp-plan-price"><b>110 ₽</b><span>разово через СБП</span></p>
"""
    + check_list(
        (
            "2 устройства, одна ссылка",
            "Без автопродления, карта не привязывается",
            "Каждая 6-я оплата — +7 дней",
        )
    )
    + """
<div class="kp-plan-actions">
<a class="restore kp-primary kp-wide" href="/pay">Купить подписку """
    + ICON_ARROW
    + """</a>
<button type="button" class="ghost kp-wide" id="open-gift">Оплатить другу</button>
</div>
<p class="muted">Разовая оплата продлевает ту же ссылку. Новая не выдаётся.</p>
</article>
<article class="kp-plan">
<p class="kp-plan-name">Пригласите друга</p>
<p class="kp-plan-price"><b>+15 дней</b><span>за каждого</span></p>
<p>Отправьте другу ссылку-приглашение. Когда он впервые получит доступ, к вашей подписке добавится 15 дней.</p>
<button type="button" class="ghost kp-wide" id="open-ref">Получить приглашение</button>
</article>
</div>
</section>

<section class="promostrip kp-promo" id="promo">
<h2>Есть промокод?</h2>
{promo_note}{promo_err}
<form method="post" action="/promo">
<div class="promorow">
<div>
<label for="promo-contact">Почта или Telegram</label>
<input id="promo-contact" name="contact" autocomplete="username" required maxlength="80" placeholder="name@mail.ru или @username" value="{promo_contact}">
</div>
<div>
<label for="promo-code">Промокод</label>
<input id="promo-code" name="code" required maxlength="32" placeholder="КОД" value="{promo_code}" autocomplete="off">
</div>
<button type="submit">Применить</button>
</div>
<div class="hp" aria-hidden="true"><input name="company" tabindex="-1" autocomplete="off"></div>
</form>
</section>

<section class="kp-section">
<h2 class="kp-h2">Частые вопросы</h2>
<div class="kp-faq">
<details><summary>Нужно ли привязывать карту для пробного периода?</summary><p>Нет. 14 дней бесплатно — почта или Telegram. Ничего не спишется само.</p></details>
<details><summary>Как оплатить, когда пробный период закончится?</summary><p>На странице <a href="/pay">оплаты</a>: 110 ₽ за 30 дней через СБП. Разовый платёж, без автопродления.</p></details>
<details><summary>Сколько устройств можно подключить?</summary><p>Два одновременно, обычно телефон и компьютер. Ссылка одна на оба.</p></details>
<details><summary>Что если ссылка потеряется?</summary><p>Письмо с той же почты на access@k-pax.space или бот с того же Telegram — робот пришлёт ссылку снова.</p></details>
</div>
<p class="kp-more"><a href="/faq">Все вопросы и ответы</a></p>
</section>

<section class="kp-cta">
<h2>Попробуйте 14 дней бесплатно</h2>
<p>Без карты и без обязательств. Понравится — 110 ₽ за месяц.</p>
<a class="restore kp-primary" href="#start">Получить ссылку """
    + ICON_ARROW
    + """</a>
</section>

<section class="kp-support">
<div>
<h2>Поддержка</h2>
<p class="muted">Жалобы, предложения и возврат — на support@k-pax.space. Ссылку возвращает робот: письмо с той же почты на access@k-pax.space или бот с того же Telegram.</p>
</div>
<div class="docbtns">
<a href="mailto:support@k-pax.space">support@k-pax.space</a>
<a href="/terms">Соглашение</a>
<a href="/privacy">Конфиденциальность</a>
<a href="/terms#refund">Возврат</a>
</div>
</section>
<p class="foot">K-Pax · 110 ₽ за 30 дней · <a href="https://t.me/kpaxvpn" rel="noopener">Канал</a> · <a href="/status">Статус</a> · <a href="/terms">Соглашение</a> · <a href="/privacy">Конфиденциальность</a> · <a href="/terms#refund">Возврат</a> · <a href="/faq">FAQ</a></p>
"""
)
