'use strict';

// Settings of the desktop app (server address, window size and zoom), kept as JSON in the user's profile.
// No Electron imports here, so the logic can be tested with plain Node.

const fs = require('fs');
const path = require('path');

const DEFAULTS = Object.freeze({
  server: '',
  bounds: { width: 1366, height: 820 },
  maximized: true,
  zoom: 0,
});

/**
 * Normalizes the server address typed by the user: adds https:// when no protocol is given,
 * removes a trailing slash, accepts only http(s). Throws an Error with an Arabic message.
 */
function normalizeServerUrl(input) {
  let s = String(input || '').trim();
  if (!s) throw new Error('أدخل عنوان الخادم');
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) s = 'https://' + s;
  let u;
  try {
    u = new URL(s);
  } catch {
    throw new Error('عنوان الخادم غير صحيح');
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') throw new Error('يجب أن يبدأ العنوان بـ https:// أو http://');
  if (!u.hostname) throw new Error('عنوان الخادم غير صحيح');
  u.hash = '';
  u.search = '';
  return u.toString().replace(/\/+$/, '');
}

/** true when url belongs to the system's server (same protocol, host and port) */
function isServerUrl(url, server) {
  if (!server) return false;
  try {
    const a = new URL(url);
    const b = new URL(server);
    return a.origin === b.origin;
  } catch {
    return false;
  }
}

/** urls the app opens inside its own windows (the rest goes to the default browser) */
function isInternalUrl(url, server) {
  return isServerUrl(url, server) || url === 'about:blank' || url.startsWith('blob:') || url.startsWith('data:');
}

function load(file) {
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    return {
      ...DEFAULTS,
      ...data,
      bounds: { ...DEFAULTS.bounds, ...(data && data.bounds) },
    };
  } catch {
    return { ...DEFAULTS, bounds: { ...DEFAULTS.bounds } };
  }
}

function save(file, config) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(config, null, 2), 'utf8');
  fs.renameSync(tmp, file);
}

module.exports = { DEFAULTS, normalizeServerUrl, isServerUrl, isInternalUrl, load, save };
