#!/usr/bin/env python3
"""Render the real XPLM page functions with disposable, non-production settings.

Usage: python server/render_xplm_preview.py --output PATH
No production configuration, mail, payment, SSH or background jobs are loaded.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


def load_panel(server: Path, temporary: Path, *, source: Path | None = None):
    config = temporary/'config.json'
    config.write_text(json.dumps({'nodes': [], 'session_secret': 'preview-only', 'brands': {'xplm': {}}}), encoding='utf-8')
    os.environ.update(KPAX_STAGE='1', KPAX_CONFIG=str(config), KPAX_DB=str(temporary/'preview.sqlite3'))
    sys.path.insert(0, str(server))
    spec = importlib.util.spec_from_file_location('xplm_preview_panel', source or server/'panel.py')
    panel = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(panel)
    return panel


def render(server: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='xplm-preview-') as directory:
        panel = load_panel(server, Path(directory))
        # Disposable synthetic data only; never open the production database.
        panel.init_db()
        now = panel.now_ts()
        conn = panel.db()
        # The production usage tables are provisioned separately from init_db.
        conn.execute("CREATE TABLE usage_month(user_key TEXT, month TEXT, proto TEXT, bytes_up INTEGER DEFAULT 0, bytes_down INTEGER DEFAULT 0, PRIMARY KEY(user_key,month,proto))")
        for index in range(1,4):
            conn.execute("INSERT INTO users(public_id,token,contact,uuid,hy2_password,created_at,expires_at,active,brand) VALUES(?,?,?,?,?,?,?,?,?)", (f'XP-DEMO-{index}',f'preview-token-{index}',f'demo{index}@example.invalid',f'preview-uuid-{index}','preview-only',now-86400*index,now+86400*14,1,'xplm'))
        for index,days in enumerate([1,3,8],1):
            stamp=now-86400*days
            conn.execute("INSERT INTO platega_invoices(transaction_id,user_id,public_id,amount,currency,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)", (f'preview-invoice-{index}',1,'XP-DEMO-1',299,'RUB','CONFIRMED',stamp,stamp))
        conn.execute("INSERT INTO cash_refunds(brand,amount,note,created_at) VALUES(?,?,?,?)",('xplm',50,'Демонстрационные данные',now-86400*2))
        conn.commit()
        conn.close()
        with panel.brand_context('xplm'):
            pages = {
                'index.html': panel.home(index=True),
                'pay/index.html': panel.pay_page(),
                'admin/cash/index.html': panel.xplm_cash_page('range=7', notice='Локальное превью: демонстрационные данные, не рабочая касса.'),
                'admin/stats/index.html': panel.xplm_stats_page(notice='Локальное превью: демонстрационные данные.'),
                'preview/cash30/index.html': panel.xplm_cash_page('range=30', notice='Локальное превью: демонстрационные данные.'),
                'status/index.html': panel.public_status_page(),
                'faq/index.html': panel.faq_page(),
                'terms/index.html': panel.terms_page(),
                'privacy/index.html': panel.privacy_page(),
                'preview/verify/index.html': panel.pending_verify_page({'contact':'example@example.com','verify_token':'preview-only'}),
                'preview/error/index.html': panel.home(error='Проверьте адрес почты и попробуйте ещё раз.', contact='example@example.com'),
                'preview/restore/index.html': panel.home(restore='email', contact='example@example.com'),
                'preview/captcha/index.html': panel.home(captcha_q='2 + 3', captcha_token='preview-only'),
                'preview/promo/index.html': panel.home(promo_error='Проверьте промокод.', promo_code='DEMO'),
                'pay/done/index.html': panel.pay_result_page('Оплата принята', 'Пример экрана после оплаты. В этом превью платёж не выполнялся.'),
                'pay/fail/index.html': panel.pay_result_page('Оплата не завершена', 'Платёж не прошёл. Можно вернуться и попробовать ещё раз.'),
            }
        for relative, (_, _, payload) in pages.items():
            path = output/relative
            path.parent.mkdir(parents=True, exist_ok=True)
            document = panel.rebrand(payload.decode('utf-8'))
            if relative == 'status/index.html':
                document = document.replace('Сервис в порядке', 'Локальное превью статуса').replace('Подключения работают.', 'Рабочие серверы в этом превью не проверяются. После публикации здесь будет действующая страница состояния.')
            path.write_text(document, encoding='utf-8')
    shutil.copy2(server/'assets/xplm-mark.svg', output/'logo.svg')
    for folder in ['assets', 'fonts']:
        (output/folder).mkdir(exist_ok=True)
    for path in (server/'assets').glob('xplm*'):
        if path.is_file():
            shutil.copy2(path, output/'assets'/path.name)
    for path in (server/'fonts').glob('manrope-*.woff2'):
        shutil.copy2(path, output/'fonts'/path.name)
    print(f'Rendered {len(pages)} real page states into {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--server', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    render(args.server.resolve(), args.output.resolve())
