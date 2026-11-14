'use strict';

// Al-Kaif Al-Asli desktop app for Windows: opens the web client of the ERP system in its own window,
// with the brand, an Arabic menu, file downloads, printing and automatic updates.

const path = require('path');
const { app, BrowserWindow, Menu, shell, ipcMain, dialog, net, session } = require('electron');
const config = require('./config');

const TITLE = 'الكيف الأصلي';
const ICON = path.join(__dirname, 'pages', 'logo.png');
const PAGES = path.join(__dirname, 'pages');

let configFile;
let settings;
let mainWindow;

if (!app.requestSingleInstanceLock()) {
  app.quit();
}

function saveSettings() {
  config.save(configFile, settings);
}

// ---------- windows ----------

/** options of the windows that show the system: no Node.js, isolated and sandboxed pages */
function webPreferences() {
  return {
    preload: path.join(__dirname, 'preload.js'),
    contextIsolation: true,
    nodeIntegration: false,
    sandbox: true,
    spellcheck: false,
  };
}

function createMainWindow() {
  const b = settings.bounds;
  mainWindow = new BrowserWindow({
    width: b.width,
    height: b.height,
    x: b.x,
    y: b.y,
    minWidth: 900,
    minHeight: 600,
    title: TITLE,
    icon: ICON,
    show: false,
    backgroundColor: '#FFF9EB',
    webPreferences: webPreferences(),
  });
  if (settings.maximized) mainWindow.maximize();
  mainWindow.once('ready-to-show', () => mainWindow.show());

  // keep the brand name in the title bar, with the page title after it
  mainWindow.on('page-title-updated', (e, title) => {
    e.preventDefault();
    mainWindow.setTitle(title && title !== TITLE ? `${TITLE} - ${title}` : TITLE);
  });

  const remember = () => {
    if (mainWindow.isDestroyed()) return;
    settings.maximized = mainWindow.isMaximized();
    if (!settings.maximized && !mainWindow.isMinimized()) settings.bounds = mainWindow.getBounds();
  };
  mainWindow.on('resize', remember);
  mainWindow.on('move', remember);
  mainWindow.on('close', () => {
    remember();
    settings.zoom = mainWindow.webContents.getZoomLevel();
    saveSettings();
  });

  setupContents(mainWindow.webContents);
  openHome();
}

/** links, new windows and load errors of a window showing the system */
function setupContents(contents) {
  contents.setWindowOpenHandler(({ url }) => {
    if (config.isInternalUrl(url, settings.server)) {
      // reports and files opened by the system in a new tab open in a new window of the app
      return {
        action: 'allow',
        overrideBrowserWindowOptions: {
          title: TITLE,
          icon: ICON,
          autoHideMenuBar: true,
          width: 1100,
          height: 800,
          webPreferences: webPreferences(),
        },
      };
    }
    openExternal(url);
    return { action: 'deny' };
  });

  contents.on('did-create-window', (win) => setupContents(win.webContents));

  contents.on('will-navigate', (e, url) => {
    if (url.startsWith('file://') || config.isInternalUrl(url, settings.server)) return;
    e.preventDefault();
    openExternal(url);
  });

  contents.on('did-fail-load', (e, code, description, url, isMainFrame) => {
    // -3: navigation aborted (not an error)
    if (!isMainFrame || code === -3 || url.startsWith('file://')) return;
    showPage(BrowserWindow.fromWebContents(contents), 'offline.html', { error: description, code: String(code) });
  });

  contents.on('did-finish-load', () => {
    if (contents === mainWindow?.webContents) contents.setZoomLevel(settings.zoom || 0);
  });
}

function openExternal(url) {
  if (/^(https?|mailto|tel):/i.test(url)) shell.openExternal(url);
}

function showPage(win, page, query = {}) {
  if (!win || win.isDestroyed()) return;
  win.loadFile(path.join(PAGES, page), { query: { server: settings.server, ...query } });
}

function openHome() {
  if (!settings.server) showPage(mainWindow, 'setup.html');
  else mainWindow.loadURL(settings.server);
}

// ---------- pages of the app (setup, offline) ----------

/** only the local pages of the app may change the settings */
function fromLocalPage(e) {
  const url = e.senderFrame?.url || '';
  return url.startsWith('file://');
}

/** checks that the server answers before saving its address */
async function checkServer(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);
  try {
    const r = await net.fetch(url, { signal: controller.signal, redirect: 'follow' });
    return r.status < 500 ? null : `الخادم أعاد خطأ (${r.status})`;
  } catch (err) {
    return `تعذر الاتصال بالخادم: ${err.message}`;
  } finally {
    clearTimeout(timer);
  }
}

ipcMain.handle('kaif:get-server', (e) => (fromLocalPage(e) ? settings.server : ''));

ipcMain.handle('kaif:save-server', async (e, input, force) => {
  if (!fromLocalPage(e)) return { error: 'غير مسموح' };
  let url;
  try {
    url = config.normalizeServerUrl(input);
  } catch (err) {
    return { error: err.message };
  }
  if (!force) {
    const error = await checkServer(url);
    if (error) return { error, canForce: true };
  }
  settings.server = url;
  saveSettings();
  openHome();
  return { ok: true };
});

ipcMain.handle('kaif:retry', (e) => {
  if (fromLocalPage(e)) openHome();
});

ipcMain.handle('kaif:change-server', (e) => {
  if (fromLocalPage(e)) showPage(mainWindow, 'setup.html');
});

// ---------- menu ----------

function zoomBy(delta) {
  const wc = BrowserWindow.getFocusedWindow()?.webContents;
  if (!wc) return;
  wc.setZoomLevel(delta === 0 ? 0 : wc.getZoomLevel() + delta);
  if (wc === mainWindow?.webContents) settings.zoom = wc.getZoomLevel();
}

function buildMenu() {
  const focused = () => BrowserWindow.getFocusedWindow();
  return Menu.buildFromTemplate([
    {
      label: 'ملف',
      submenu: [
        { label: 'الصفحة الرئيسية', accelerator: 'Alt+Home', click: () => openHome() },
        { label: 'إعادة تحميل', accelerator: 'F5', click: () => focused()?.webContents.reload() },
        { label: 'طباعة', accelerator: 'Ctrl+P', click: () => focused()?.webContents.print() },
        { type: 'separator' },
        { label: 'تغيير عنوان الخادم', click: () => showPage(mainWindow, 'setup.html') },
        { type: 'separator' },
        { label: 'خروج', accelerator: 'Alt+F4', role: 'quit' },
      ],
    },
    {
      label: 'تحرير',
      submenu: [
        { label: 'تراجع', role: 'undo' },
        { label: 'إعادة', role: 'redo' },
        { type: 'separator' },
        { label: 'قص', role: 'cut' },
        { label: 'نسخ', role: 'copy' },
        { label: 'لصق', role: 'paste' },
        { label: 'تحديد الكل', role: 'selectAll' },
      ],
    },
    {
      label: 'عرض',
      submenu: [
        { label: 'تكبير', accelerator: 'Ctrl+=', click: () => zoomBy(0.5) },
        { label: 'تصغير', accelerator: 'Ctrl+-', click: () => zoomBy(-0.5) },
        { label: 'الحجم الافتراضي', accelerator: 'Ctrl+0', click: () => zoomBy(0) },
        { type: 'separator' },
        { label: 'ملء الشاشة', accelerator: 'F11', role: 'togglefullscreen' },
      ],
    },
    {
      label: 'مساعدة',
      submenu: [
        { label: 'البحث عن تحديثات', click: () => checkForUpdates(true) },
        { label: 'أدوات المطور', accelerator: 'Ctrl+Shift+I', click: () => focused()?.webContents.toggleDevTools() },
        { type: 'separator' },
        {
          label: 'حول البرنامج',
          click: () =>
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              title: TITLE,
              icon: ICON,
              message: TITLE,
              detail: `الإصدار ${app.getVersion()}\nالخادم: ${settings.server || 'غير محدد'}`,
              buttons: ['حسناً'],
            }),
        },
      ],
    },
  ]);
}

// ---------- updates ----------

async function checkForUpdates(manual) {
  if (!app.isPackaged) {
    if (manual) dialog.showMessageBox(mainWindow, { message: 'التحديث التلقائي يعمل في النسخة المثبتة فقط', buttons: ['حسناً'] });
    return;
  }
  const { autoUpdater } = require('electron-updater');
  autoUpdater.autoDownload = true;
  autoUpdater.removeAllListeners();
  autoUpdater.on('update-downloaded', async (info) => {
    const r = await dialog.showMessageBox(mainWindow, {
      type: 'info',
      title: TITLE,
      message: `تم تحميل الإصدار ${info.version}`,
      detail: 'سيتم تثبيته عند إغلاق البرنامج، أو أعد التشغيل الآن.',
      buttons: ['إعادة التشغيل الآن', 'لاحقاً'],
      defaultId: 0,
    });
    if (r.response === 0) autoUpdater.quitAndInstall();
  });
  if (manual) {
    autoUpdater.once('update-not-available', () =>
      dialog.showMessageBox(mainWindow, { message: 'لديك أحدث إصدار', buttons: ['حسناً'] }));
    autoUpdater.once('error', (err) =>
      dialog.showMessageBox(mainWindow, { type: 'warning', message: 'تعذر البحث عن تحديثات', detail: String(err), buttons: ['حسناً'] }));
  }
  try {
    await autoUpdater.checkForUpdates();
  } catch {
    // no network: checked again on the next start
  }
}

// ---------- start ----------

app.on('second-instance', () => {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
});

app.whenReady().then(() => {
  app.setAppUserModelId('sa.alkaif.desktop');
  configFile = path.join(app.getPath('userData'), 'config.json');
  settings = config.load(configFile);

  // camera (barcode scanning), location, notifications and clipboard: only for the system's server
  session.defaultSession.setPermissionRequestHandler((wc, permission, callback, details) => {
    const allowed = ['media', 'geolocation', 'notifications', 'clipboard-read', 'clipboard-sanitized-write', 'fullscreen'];
    callback(allowed.includes(permission) && config.isServerUrl(details.requestingUrl || wc.getURL(), settings.server));
  });

  Menu.setApplicationMenu(buildMenu());
  createMainWindow();
  setTimeout(() => checkForUpdates(false), 5000);
});

app.on('window-all-closed', () => app.quit());
