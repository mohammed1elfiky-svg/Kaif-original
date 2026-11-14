'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { normalizeServerUrl, isServerUrl, isInternalUrl, load, save, DEFAULTS } = require('../src/config');

test('server address: protocol added, trailing slash removed', () => {
  assert.strictEqual(normalizeServerUrl('erp.alkaif.sa'), 'https://erp.alkaif.sa');
  assert.strictEqual(normalizeServerUrl(' https://erp.alkaif.sa/ '), 'https://erp.alkaif.sa');
  assert.strictEqual(normalizeServerUrl('http://192.168.1.10:8080/'), 'http://192.168.1.10:8080');
  assert.strictEqual(normalizeServerUrl('https://erp.alkaif.sa/kaif/?x=1#a'), 'https://erp.alkaif.sa/kaif');
});

test('server address: invalid input', () => {
  assert.throws(() => normalizeServerUrl(''), /أدخل عنوان الخادم/);
  assert.throws(() => normalizeServerUrl('ftp://erp.alkaif.sa'), /https/);
  assert.throws(() => normalizeServerUrl('https://'), /غير صحيح/);
});

test('internal and external links', () => {
  const server = 'https://erp.alkaif.sa';
  assert.ok(isServerUrl('https://erp.alkaif.sa/main', server));
  assert.ok(!isServerUrl('https://erp.alkaif.sa:8443/main', server));
  assert.ok(!isServerUrl('http://erp.alkaif.sa/main', server));
  assert.ok(!isServerUrl('https://evil.example/https://erp.alkaif.sa', server));
  assert.ok(!isServerUrl('https://erp.alkaif.sa.evil.example/', server));
  assert.ok(!isServerUrl('https://erp.alkaif.sa/', ''));
  assert.ok(isInternalUrl('about:blank', server));
  assert.ok(isInternalUrl('blob:https://erp.alkaif.sa/123', server));
  assert.ok(!isInternalUrl('https://www.google.com/maps', server));
});

test('settings: defaults, save and load', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kaif-'));
  const file = path.join(dir, 'sub', 'config.json');
  assert.deepStrictEqual(load(file), { ...DEFAULTS, bounds: { ...DEFAULTS.bounds } });
  save(file, { ...load(file), server: 'https://erp.alkaif.sa', bounds: { width: 1000, height: 700, x: 5, y: 6 } });
  const c = load(file);
  assert.strictEqual(c.server, 'https://erp.alkaif.sa');
  assert.deepStrictEqual(c.bounds, { width: 1000, height: 700, x: 5, y: 6 });
  assert.strictEqual(c.maximized, true);
  fs.writeFileSync(file, '{broken');
  assert.strictEqual(load(file).server, '');
});
