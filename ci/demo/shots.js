// Screenshots of the demo run: logs in to the web client and opens each form of the presentation
// (the form is set through the API and shown by the test module on the start of the web client).
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = process.env.BASE || 'http://localhost:8080';
const OUT = process.env.OUT || 'shots';
const AUTH = 'Basic ' + Buffer.from('admin:').toString('base64');

const screens = [
  ['02-items', 'SHOW MasterData.items'],
  ['03-partners', 'SHOW MasterData.partners'],
  ['04-invoices', 'SHOW Invoicing.invoices'],
  ['05-invoice', 'SHOW Invoicing.invoice OBJECTS i = KaifTest.lastInvoice()'],
  ['06-payments', 'SHOW Invoicing.incomingPayments'],
  ['07-returns', 'SHOW Invoicing.bills'],
  ['08-vat-return', 'SHOW Invoicing.vatReturnSa'],
  ['09-online-stores', 'SHOW Ecommerce.ecommerceStores'],
  ['10-activation', 'SHOW Kaif.licenseSa'],
];

async function setForm(f) {
  const r = await fetch(`${BASE}/exec?action=KaifTest.setDemoForm&p=${encodeURIComponent(f)}`, { headers: { Authorization: AUTH } });
  if (!r.ok) console.log('setDemoForm', f, r.status, await r.text());
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'ar-SA' });
  page.on('pageerror', e => console.log('pageerror:', e.message));

  await setForm('');
  await page.goto(`${BASE}/login`);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${OUT}/00-login.png` });
  await page.fill('#username', 'admin');
  await page.fill('#password', '');
  await Promise.all([page.waitForNavigation({ timeout: 60000 }).catch(() => {}), page.press('#password', 'Enter')]);
  await page.waitForTimeout(12000);
  await page.screenshot({ path: `${OUT}/01-main.png` });

  for (const [name, form] of screens) {
    try {
      await setForm(form);
      await page.goto(`${BASE}/main`);
      await page.waitForTimeout(10000);
      await page.screenshot({ path: `${OUT}/${name}.png` });
      console.log('ok', name);
    } catch (e) {
      console.log('failed', name, e.message);
    }
  }
  await setForm('');
  await browser.close();
})();
