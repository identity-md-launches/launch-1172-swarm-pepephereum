import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { chromium } from '../test/scratch/site-tools/node_modules/playwright/index.mjs';
import AxeBuilder from '../test/scratch/site-tools/node_modules/@axe-core/playwright/dist/index.mjs';
import { startServer } from './server.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
process.env.PLAYWRIGHT_BROWSERS_PATH ||= path.join(root, 'test/scratch/browsers');
let browser, server, url;
// Synthetic data exists only in intercepted test responses, never in the export.
const token = `0x${randomBytes(20).toString('hex')}`;
const live = () => ({ name: 'Swarm PEPEPHEREUM', symbol: 'SPEPE', token,
  chainName: 'Robinhood Chain', coinUrl: '/test-launch', chartUrl: '/test-chart', status: 'live',
  logo: '/preview/assets/spepe.webp?replacement',
  market: { marketCap: 1234567.89, priceUsd: 0.00000042, volume24h: 0 } });
const evidence = { viewports: [], accessibility: [], interactions: [], generatedAt: new Date().toISOString() };

before(async () => {
  ({ server, url } = await startServer());
  browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
});
after(async () => {
  await browser?.close();
  await new Promise(resolve => server?.close(resolve));
  await mkdir(path.join(root, 'test/scratch/site-results'), { recursive: true });
  await writeFile(path.join(root, 'test/scratch/site-results/results.json'), JSON.stringify(evidence, null, 2));
});

async function open(t, { payload = {}, width = 1440, status = 200, javaScriptEnabled = true } = {}) {
  const context = await browser.newContext({ viewport: { width, height: 1000 }, javaScriptEnabled,
    permissions: ['clipboard-read', 'clipboard-write'] });
  t.after(() => context.close());
  const page = await context.newPage();
  const errors = [], failed = [], resources = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('requestfailed', request => failed.push(request.url()));
  page.on('response', response => resources.push({ url: response.url(), status: response.status() }));
  await page.route('**/simd-coin.json', route => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(payload) }));
  await page.goto(url);
  if (javaScriptEnabled) await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  await page.evaluate(() => document.fonts.ready);
  return { page, context, errors, failed, resources };
}

test('production export is complete, byte-identical to source, and uses relative runtime asset paths', async () => {
  async function walk(directory, prefix = '') {
    for (const item of await readdir(directory, { withFileTypes: true })) {
      const relative = path.join(prefix, item.name);
      if (item.isDirectory()) await walk(path.join(directory, item.name), relative);
      else assert.deepEqual(await readFile(path.join(root, 'dist', relative)), await readFile(path.join(directory, item.name)), relative);
    }
  }
  await walk(path.join(root, 'site'));
  const html = await readFile(path.join(root, 'dist/index.html'), 'utf8');
  assert.equal((html.match(/<h1\b/g) || []).length, 1);
  assert.equal((html.match(/<main\b/g) || []).length, 1);
  assert(!/<form\b|walletconnect|googletagmanager/i.test(html));
  for (const [, value] of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
    assert(value.startsWith('./') || value.startsWith('#') || value === 'https://www.si-md.xyz/launchpad/', value);
  }
});

test('prelaunch has honest empty states, disabled trading and no address to copy', async t => {
  const { page, errors, failed, resources } = await open(t);
  assert.equal(await page.locator('#contract').innerText(), 'launching…');
  assert.equal(await page.locator('#buy').getAttribute('href'), null);
  assert.equal(await page.locator('#chart').getAttribute('href'), null);
  assert(await page.locator('#copy').isDisabled());
  assert.equal(await page.locator('#price [data-display]').innerText(), '—');
  assert.equal(await page.locator('#feed-state').innerText(), 'Awaiting launch');
  await page.locator('nav a[href="#how"]').click();
  assert(url.endsWith('/preview/')); assert(page.url().endsWith('#how'));
  assert(await page.locator('#how-title').isVisible());
  await page.locator('summary').press('Enter');
  assert.equal(await page.locator('details').getAttribute('open'), '');
  await page.locator('summary').press('Space');
  assert.equal(await page.locator('details').getAttribute('open'), null);
  assert.deepEqual(errors, []); assert.deepEqual(failed, []);
  assert(resources.every(r => r.status === 200));
  assert(resources.every(r => r.url.startsWith(new URL(url).origin)));
  evidence.interactions.push('Prelaunch, anchor navigation, keyboard disclosure; all runtime assets local with HTTP 200.');
});

test('live feed populates precise market values, preferred logo, full address, clipboard and exact trading destinations', async t => {
  const { page, errors, resources } = await open(t, { payload: live() });
  assert.equal(await page.locator('#contract').innerText(), token);
  assert.equal(await page.locator('#market-cap [data-display]').innerText(), '$1.23M');
  assert.equal(await page.locator('#market-cap').getAttribute('title'), '1,234,567.89 US dollars');
  assert.equal(await page.locator('#price [data-display]').innerText(), '$4.20e-7');
  assert.equal(await page.locator('#volume [data-display]').innerText(), '$0.00');
  assert.equal(await page.locator('#market-cap .sr-only').textContent(), '1,234,567.89 US dollars');
  assert.equal(await page.locator('#logo').getAttribute('src'), new URL('/preview/assets/spepe.webp?replacement', url).href);
  assert.equal(await page.locator('#logo').getAttribute('alt'), 'Swarm PEPEPHEREUM logo');
  assert.equal(await page.locator('#status').textContent(), 'live');
  await page.locator('#copy').click();
  await page.waitForFunction(() => document.querySelector('#announcement').textContent.includes('copied'));
  assert.equal(await page.evaluate(() => navigator.clipboard.readText()), token);
  await page.route('**/test-launch', route => route.fulfill({ body: '<title>Launch test destination</title>' }));
  await page.locator('#buy').click();
  assert.equal(new URL(page.url()).pathname, '/test-launch');
  await page.goBack();
  await page.waitForFunction(() => document.querySelector('#chart').hasAttribute('href'));
  await page.route('**/test-chart', route => route.fulfill({ body: '<title>Chart test destination</title>' }));
  await page.locator('#chart').click();
  assert.equal(new URL(page.url()).pathname, '/test-chart');
  assert.deepEqual(errors, []);
  assert(resources.some(r => r.url.includes('replacement') && r.status === 200));
  evidence.interactions.push('Live JSON, tiny price, real zero, full market tooltip, logo override, browser clipboard write/read, Buy and Chart navigation.');
});

test('404 and malformed JSON recover via Refresh; valid old data is explicitly stale on failure', async t => {
  const { page } = await open(t, { status: 404 });
  assert.equal(await page.locator('#feed-state').innerText(), 'Update unavailable');
  assert.equal(await page.locator('#buy').getAttribute('href'), null);
  await page.route('**/simd-coin.json', route => route.fulfill({ body: '{broken', contentType: 'application/json' }));
  await page.locator('#refresh').click();
  await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  assert.match(await page.locator('#announcement').innerText(), /Could not load/);
  await page.route('**/simd-coin.json', route => route.fulfill({ json: live() }));
  await page.locator('#refresh').click();
  await page.waitForFunction(() => document.querySelector('#contract').textContent.startsWith('0x'));
  await page.route('**/simd-coin.json', route => route.fulfill({ status: 503, body: '' }));
  await page.locator('#refresh').click();
  await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  assert.match(await page.locator('#feed-note').innerText(), /Showing the last update/);
  assert.equal(await page.locator('#contract').innerText(), token);
  evidence.interactions.push('Missing endpoint, malformed JSON, 503 after success, manual recovery and stale-data message.');
});

test('malicious URLs and malformed addresses are never actionable; text stays literal', async t => {
  const input = { ...live(), name: '<img src=x onerror=alert(1)>', token: 'not-an-address',
    coinUrl: 'javascript:alert(1)', chartUrl: 'data:text/html,hello', logo: 'javascript:alert(2)',
    market: { priceUsd: -1, volume24h: 'NaN', marketCap: 'Infinity' } };
  const { page, errors } = await open(t, { payload: input });
  assert.equal(await page.locator('h1').innerText(), input.name);
  assert.equal(await page.locator('h1 img').count(), 0);
  assert.equal(await page.locator('#contract').innerText(), 'launching…');
  assert.equal(await page.locator('#buy').getAttribute('href'), null);
  assert.equal(await page.locator('#chart').getAttribute('href'), null);
  assert((await page.locator('#logo').getAttribute('src')).endsWith('/assets/spepe.webp'));
  for (const id of ['price', 'volume', 'market-cap']) assert.equal(await page.locator(`#${id} [data-display]`).innerText(), '—');
  // A real-shaped address must not bypass URL validation.
  await page.route('**/simd-coin.json', route => route.fulfill({ json: { ...input, token } }));
  await page.locator('#refresh').click();
  await page.waitForFunction(() => document.querySelector('#contract').textContent.startsWith('0x'));
  assert.equal(await page.locator('#buy').getAttribute('href'), null);
  assert.equal(await page.locator('#chart').getAttribute('href'), null);
  assert.deepEqual(errors, []);
  evidence.interactions.push('Literal text rendering, unsafe URL schemes, invalid address and invalid market values.');
});

test('missing individual links stay unavailable and an absent token cannot enable either link', async t => {
  const { page } = await open(t, { payload: { ...live(), chartUrl: null } });
  assert(await page.locator('#buy').getAttribute('href'));
  assert.equal(await page.locator('#chart').getAttribute('href'), null);
  await page.route('**/simd-coin.json', route => route.fulfill({ json: { ...live(), token: null } }));
  await page.locator('#refresh').click();
  await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  assert.equal(await page.locator('#buy').getAttribute('href'), null);
  assert.equal(await page.locator('#chart').getAttribute('href'), null);
  assert.equal(await page.locator('#status').textContent(), 'Launching');
});

test('failed replacement logo falls back locally and denied clipboard provides manual recovery', async t => {
  const { page } = await open(t, { payload: { ...live(), logo: '/preview/assets/missing.webp' } });
  await page.waitForFunction(() => document.querySelector('#logo').src.endsWith('/assets/spepe.webp'));
  assert(await page.locator('#logo').evaluate(image => image.complete && image.naturalWidth > 0));
  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => { throw new Error('Denied'); } } }));
  await page.locator('#copy').click();
  await page.waitForFunction(() => document.querySelector('#announcement').textContent.includes('Could not copy'));
  assert.equal(await page.evaluate(() => window.getSelection().toString()), token);
  assert.match(await page.locator('#feed-note').innerText(), /Select and copy the full contract/);
  assert(await page.locator('#copy').isEnabled());
  evidence.interactions.push('Broken remote logo fallback and clipboard denial with selectable full address.');
});

test('automatic refresh uses a short virtual clock, pauses while hidden, and handles timeout', async t => {
  const { page } = await open(t);
  await page.clock.install();
  await page.route('**/simd-coin.json', route => route.fulfill({ json: live() }));
  // Install before reload so application timers are controlled by the virtual clock.
  await page.reload();
  await page.waitForFunction(() => document.querySelector('#contract').textContent.startsWith('0x'));
  let polls = 0;
  await page.route('**/simd-coin.json', route => { polls++; return route.fulfill({ json: live() }); });
  await page.clock.fastForward(30_001);
  await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  assert.equal(polls, 1);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.clock.fastForward(60_000);
  assert.equal(polls, 1);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, value: false });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  assert.equal(polls, 2);
  await page.route('**/simd-coin.json', () => {});
  await page.locator('#refresh').click();
  assert(await page.locator('#refresh').isDisabled());
  await page.clock.fastForward(8001);
  await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  assert.match(await page.locator('#feed-note').innerText(), /Could not refresh/);
  evidence.interactions.push('30-second polling, hidden-tab pause/resume and 8-second timeout tested with virtual time.');
});

test('responsive export has no horizontal overflow, loaded fonts, visible focus and no axe WCAG A/AA findings', async t => {
  const { page, errors, failed } = await open(t, { payload: live() });
  for (const width of [1440, 1060, 900, 768, 720, 576, 390, 320]) {
    await page.setViewportSize({ width, height: 1000 });
    const layout = await page.evaluate(() => ({ width: innerWidth, scroll: document.documentElement.scrollWidth,
      fonts: [...document.fonts].map(f => ({ family: f.family, status: f.status })),
      clipped: [...document.querySelectorAll('h1,h2,h3,p,code,.button')].filter(e => !e.classList.contains('sr-only') && e.scrollWidth > e.clientWidth + 1).map(e => e.id || e.className) }));
    assert.equal(layout.scroll, width, `Horizontal overflow at ${width}px`);
    assert.deepEqual(layout.clipped, [], `Clipped content at ${width}px`);
    assert(layout.fonts.every(font => font.status === 'loaded'));
    evidence.viewports.push(layout);
  }
  for (const width of [1440, 390, 320]) {
    await page.setViewportSize({ width, height: 1000 });
    const result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
    evidence.accessibility.push({ width, violations: result.violations, incomplete: result.incomplete.map(i => ({ id: i.id, nodes: i.nodes.length })) });
    assert.deepEqual(result.violations.map(v => ({ id: v.id, impact: v.impact, nodes: v.nodes.map(n => n.target) })), []);
    assert.deepEqual(result.incomplete.filter(i => i.id !== 'color-contrast').map(i => i.id), []);
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto(url);
  await page.waitForFunction(() => document.querySelector('#buy').hasAttribute('href'));
  await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(() => document.activeElement.textContent), 'Skip to content');
  await page.keyboard.press('Enter');
  assert.equal(await page.evaluate(() => document.activeElement.id), 'main');
  await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(() => document.activeElement.id), 'buy');
  const focus = await page.locator('#buy').evaluate(el => ({ width: getComputedStyle(el).outlineWidth, style: getComputedStyle(el).outlineStyle }));
  assert.deepEqual(focus, { width: '3px', style: 'solid' });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  assert.equal(await page.locator('#buy').evaluate(el => getComputedStyle(el).transitionDuration), '0s');
  await page.emulateMedia({ forcedColors: 'active' });
  assert.equal(await page.locator('#buy').evaluate(el => getComputedStyle(el).outlineStyle), 'solid');
  assert.deepEqual(errors, []); assert.deepEqual(failed, []);
  evidence.interactions.push('Skip link and primary action by keyboard, reduced motion and forced-colors focus.');
});

test('200 percent text enlargement and long feed names reflow; no-JavaScript content remains usable', async t => {
  const { page } = await open(t, { payload: { ...live(), name: 'Swarm PEPEPHEREUM With A Much Longer Name For Layout Testing', symbol: 'SPEPEEXTENDEDSYMBOL' }, width: 390 });
  await page.addStyleTag({ content: 'html { font-size: 200%; }' });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 390);
  await page.locator('summary').click();
  assert(await page.locator('.details-body').isVisible());
  const noJs = await open(t, { javaScriptEnabled: false, width: 320 });
  assert(await noJs.page.locator('noscript').isVisible());
  assert.equal(await noJs.page.locator('#contract').innerText(), 'launching…');
  await noJs.page.locator('nav a[href="#tokenomics"]').click();
  assert(noJs.page.url().endsWith('#tokenomics'));
  await noJs.page.locator('summary').click();
  assert(await noJs.page.locator('.details-body').isVisible());
  assert.equal(await noJs.page.evaluate(() => document.documentElement.scrollWidth), 320);
  evidence.interactions.push('200% CSS text enlargement with long feed strings; no-JavaScript navigation and disclosure. This is not native browser zoom.');
});
