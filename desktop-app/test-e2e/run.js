// End-to-end check of the desktop app with Playwright's Electron driver and a fake ERP server.
// Run (Linux): xvfb-run node test-e2e/run.js <screenshots dir>   (needs the playwright package)
const { _electron: electron } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const APP = path.join(__dirname, '..');
const OUT = process.argv[2];

const page = (title, body) => `<!doctype html><html dir="rtl"><head><meta charset="utf-8"><title>${title}</title></head>
<body style="font-family:DejaVu Sans;background:#fff"><h1>${title}</h1>${body}</body></html>`;
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  if (req.url.startsWith('/report')) return res.end(page('تقرير', '<p>report window</p>'));
  res.end(page('لوحة المعلومات', `<p id="api">${'${'}typeof window.kaif}</p>
    <a id="open" href="/report" target="_blank">open report</a>
    <a id="ext" href="https://example.com/" target="_blank">external</a>
    <script>document.getElementById('api').textContent = 'kaif api on server page: ' + typeof window.kaif;</script>`));
});

(async () => {
  await new Promise((r) => server.listen(18080, '127.0.0.1', r));
  const userData = fs.mkdtempSync(path.join(os.tmpdir(), 'kaif-desktop-'));
  const app = await electron.launch({
    executablePath: require(path.join(APP, 'node_modules/electron')),
    args: [APP, `--user-data-dir=${userData}`, '--no-sandbox'],
  });
  const results = [];
  const check = (name, ok) => { results.push(`${ok ? 'PASS' : 'FAIL'} ${name}`); };

  // 1. first start: setup page
  let win = await app.firstWindow();
  await win.waitForLoadState('domcontentloaded');
  check('first start shows the setup page', win.url().includes('setup.html'));
  await win.setViewportSize({ width: 1000, height: 700 }).catch(() => {});
  await win.screenshot({ path: `${OUT}/1_setup.png` });

  // invalid address
  await win.fill('#server', 'ftp://x');
  await win.click('#save');
  await win.waitForFunction(() => document.getElementById('error').textContent.length > 0);
  check('invalid address rejected', (await win.textContent('#error')).includes('https'));

  // unreachable server: error + "save anyway"
  await win.fill('#server', 'http://127.0.0.1:18099');
  await win.click('#save');
  await win.waitForFunction(() => !document.getElementById('force').hidden, null, { timeout: 15000 });
  check('unreachable server reported', (await win.textContent('#error')).includes('تعذر الاتصال'));
  await win.screenshot({ path: `${OUT}/2_setup_error.png` });

  // 2. valid server
  await win.fill('#server', '127.0.0.1:18080'.replace(/^/, 'http://'));
  await win.click('#save');
  await win.waitForURL('http://127.0.0.1:18080/**');
  await win.waitForSelector('#api');
  const title = await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].getTitle());
  check(`brand in the title: "${title}"`, title === 'الكيف الأصلي - لوحة المعلومات');
  check('server pages have no access to the app API', (await win.textContent('#api')).includes('undefined'));
  await win.screenshot({ path: `${OUT}/3_system.png` });

  // 3. new windows: internal in the app, external not
  const [report] = await Promise.all([app.waitForEvent('window'), win.click('#open')]);
  await report.waitForLoadState('domcontentloaded');
  check('report opens in a new app window', report.url().endsWith('/report'));
  await report.close();
  await win.click('#ext');
  await new Promise((r) => setTimeout(r, 1000));
  const count = await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length);
  check('external link does not open inside the app', count === 1);

  // settings saved
  const cfg = JSON.parse(fs.readFileSync(path.join(userData, 'config.json'), 'utf8'));
  check('server address saved', cfg.server === 'http://127.0.0.1:18080');

  // 4. server down: offline page
  server.closeAllConnections();
  await new Promise((r) => server.close(r));
  await win.reload().catch(() => {});
  await win.waitForURL(/offline\.html/, { timeout: 15000 });
  check('offline page when the server is down', win.url().includes('offline.html'));
  await win.screenshot({ path: `${OUT}/4_offline.png` });

  // menu
  const menu = await app.evaluate(({ Menu }) => Menu.getApplicationMenu().items.map((i) => i.label));
  check(`Arabic menu: ${menu.join(' | ')}`, menu[0] === 'ملف' && menu.length === 4);

  await app.close();
  console.log(results.join('\n'));
  process.exit(results.some((r) => r.startsWith('FAIL')) ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
