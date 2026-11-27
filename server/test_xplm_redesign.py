"""Presentation contract tests, isolated from production and external services."""
import ast
from collections import Counter
from html.parser import HTMLParser
import importlib.util
from pathlib import Path
import re
import string
import tempfile
import unittest

from render_xplm_preview import load_panel
import xplm_templates


class Document(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.elements = []
        self.text = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        self.elements.append((tag, dict(attrs)))

    def handle_data(self, data):
        self.text.append(data)


class RedesignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = Path(__file__).resolve().parent
        cls.temporary = tempfile.TemporaryDirectory(prefix='xplm-design-test-')
        cls.panel = load_panel(cls.server, Path(cls.temporary.name))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def home(self, **kwargs):
        with self.panel.brand_context('xplm'):
            status, _, payload = self.panel.home(**kwargs)
        return status, self.panel.rebrand(payload.decode('utf-8'))

    def test_existing_template_parameters_and_form_contracts(self):
        fields = {field for _, field, _, _ in string.Formatter().parse(xplm_templates.HOME) if field}
        self.assertEqual(fields, {'android_url','contact','captcha_fields','ref_field','ref_note','note','action','err','submit','legal','apps_hint','promo_note','promo_err','promo_contact','promo_code'})
        status, html = self.home(captcha_q='2 + 3', captcha_token='protected-token')
        self.assertEqual(status, 200)
        doc = Document(html)
        ids = [a['id'] for _, a in doc.elements if 'id' in a]
        self.assertFalse([key for key, count in Counter(ids).items() if count > 1])
        self.assertTrue({'contact','captcha','open-gift','open-ref','ref-modal','gift-modal','close-ref','close-gift','promo-contact','promo-code'}.issubset(ids))
        self.assertTrue({'/signup','/promo','/pay'}.issubset({a.get('action') for tag,a in doc.elements if tag == 'form'}))
        self.assertIn('protected-token', html)
        self.assertIn('name="captcha_token"', html)
        self.assertEqual(sum(1 for tag,a in doc.elements if tag == 'input' and a.get('name') == 'company'), 3)
        for tag, attrs in doc.elements:
            if tag == 'a' and attrs.get('href', '').startswith('#'):
                self.assertIn(attrs['href'][1:], ids)

    def test_message_states_restore_and_escaping(self):
        status, html = self.home(error='<script>alert(1)</script>', contact='a"<@example.com')
        self.assertEqual(status, 400)
        self.assertIn('&lt;script&gt;alert(1)&lt;/script&gt;', html)
        self.assertIn('a&quot;&lt;@example.com', html)
        _, restored = self.home(restore='email', contact='example@example.com')
        doc = Document(restored)
        self.assertTrue(any(a.get('id') == 'resend-mail' for _,a in doc.elements))
        self.assertFalse(any(tag == 'button' and a.get('type') == 'submit' for tag,a in doc.elements[:next(i for i,(tag,a) in enumerate(doc.elements) if a.get('id') == 'apps')]))
        _, promo = self.home(promo_error='Неверный промокод', promo_code='DEMO')
        self.assertIn('Неверный промокод', promo)
        self.assertIn('value="DEMO"', promo)

    def test_all_public_pages_keep_brand_and_existing_routes(self):
        with self.panel.brand_context('xplm'):
            pages = [self.panel.home(index=True), self.panel.pay_page(), self.panel.faq_page(), self.panel.terms_page(), self.panel.privacy_page(), self.panel.pending_verify_page({'contact':'example@example.com','verify_token':'preview-only'})]
        for _, _, payload in pages:
            html = self.panel.rebrand(payload.decode())
            self.assertIn('xp-header', html)
            self.assertIn('/assets/xplm.css?v=' + self.panel.XPLM_ASSETS, html)
            self.assertNotRegex(html, r'(?i)\bVPN\b|ВПН')
            self.assertNotRegex(''.join(Document(html).text), r'K-Pax|k-pax\.space|110 ₽')
        payment = self.panel.rebrand(pages[1][2].decode())
        self.assertIn('299 ₽', payment)
        self.assertIn('method="post" action="/pay"', payment)
        verify = self.panel.rebrand(pages[-1][2].decode())
        self.assertIn('action="/verify"', verify)
        self.assertIn('action="/verify/resend"', verify)

    def test_assets_and_synchronized_edge_copies(self):
        assets = ['xplm.css','xplm-site.js','xplm-mark.svg','xplm-hero.webp','xplm-devices.webp','xplm-lifestyle.webp']
        for name in assets:
            origin = self.server/'assets'/name
            self.assertTrue(origin.is_file(), name)
            self.assertEqual(origin.read_bytes(), (self.server/'x-plm/assets'/name).read_bytes())
        self.assertEqual((self.server/'xplm_templates.py').read_bytes(), (self.server/'x-plm/xplm_templates.py').read_bytes())
        self.assertEqual((self.server/'assets/xplm.css').read_bytes(), (self.server/'x-plm/xplm.css').read_bytes())
        css = (self.server/'assets/xplm.css').read_text(encoding='utf-8')
        for url in re.findall(r'url\([\'"]?([^\)\'\"]+)', css):
            if url.startswith('/'):
                self.assertTrue((self.server/url.split('?',1)[0].lstrip('/')).is_file(), url)
        self.assertIn('[hidden],.hp{display:none!important}', css)
        self.assertIn('prefers-reduced-motion', css)

    def test_reporting_keeps_cash_filters_refund_contract_and_statistics(self):
        self.panel.init_db()
        conn = self.panel.db()
        conn.execute("CREATE TABLE IF NOT EXISTS usage_month(user_key TEXT,month TEXT,proto TEXT,bytes_up INTEGER,bytes_down INTEGER)")
        conn.commit()
        conn.close()
        with self.panel.brand_context('xplm'):
            status, _, cash = self.panel.xplm_cash_page('range=7')
            stats_status, _, stats = self.panel.xplm_stats_page()
        self.assertEqual((status,stats_status),(200,200))
        doc=Document(cash.decode())
        forms=[a for tag,a in doc.elements if tag=='form']
        self.assertTrue(any(a.get('method')=='get' and a.get('action')=='/admin/cash' for a in forms))
        self.assertTrue(any(a.get('method')=='post' and a.get('action')=='/admin/cash/refund' for a in forms))
        inputs={a.get('name'):a for tag,a in doc.elements if tag=='input'}
        self.assertTrue({'range','from','to','amount','note'}.issubset(inputs))
        self.assertEqual(inputs['amount']['value'],'299')
        self.assertEqual(inputs['amount']['max'],'100000')
        self.assertEqual(inputs['amount']['min'],'1')
        self.assertEqual(inputs['amount']['step'],'1')
        self.assertIn('cash-chart',cash.decode())
        self.assertEqual(sum(1 for tag,a in Document(stats.decode()).elements if tag=='article' and a.get('class')=='health'),8)

    def test_kpax_keeps_its_original_template_and_shell(self):
        with self.panel.brand_context('kpax'):
            _, _, payload = self.panel.home()
        html = payload.decode()
        self.assertIn('kpax.css', html)
        self.assertNotIn('xplm.css', html)
        self.assertNotIn('xp-header', html)
        self.assertNotIn('xplm-hero.webp', html)
        self.assertIn('K-Pax', html)


if __name__ == '__main__':
    unittest.main()
