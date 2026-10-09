import { chromium } from '../test/scratch/site-tools/node_modules/playwright/index.mjs';
import { mkdir, writeFile } from 'node:fs/promises';
import { startServer } from './server.mjs';

// Run with `node site-tools/check.mjs review` so the ignored browser installation is used.
const { server, url } = await startServer();
const browser = await chromium.launch({ args: ['--no-sandbox'] });
try {
  await mkdir('docs/site-review', { recursive: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1050 } });
  await page.goto(url);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => !document.querySelector('#refresh').disabled);
  await page.screenshot({ path: 'docs/site-review/desktop.webp', type: 'webp', quality: 68, fullPage: true });
  const contrast = await page.evaluate(() => {
    const pairs = new Map();
    const rgb = value => value.match(/[\d.]+/g).map(Number);
    const luminance = value => value.slice(0, 3).map(n => {
      n /= 255;
      return n <= .04045 ? n / 12.92 : ((n + .055) / 1.055) ** 2.4;
    }).reduce((sum, n, i) => sum + n * [.2126, .7152, .0722][i], 0);
    const ratio = (a, b) => (Math.max(luminance(rgb(a)), luminance(rgb(b))) + .05) / (Math.min(luminance(rgb(a)), luminance(rgb(b))) + .05);
    for (const element of document.querySelectorAll('body *')) {
      if (element.closest('.sr-only,noscript') || !element.getClientRects().length ||
        ![...element.childNodes].some(node => node.nodeType === 3 && node.textContent.trim())) continue;
      // Keep visible market spans, even though their full accessible value is separate.
      if (element.closest('[aria-hidden="true"]') && !element.hasAttribute('data-display')) continue;
      const style = getComputedStyle(element);
      let parent = element, background;
      while (parent) {
        const color = getComputedStyle(parent).backgroundColor;
        if (rgb(color).length === 3 || rgb(color)[3] === 1) { background = color; break; }
        parent = parent.parentElement;
      }
      if (!background) continue;
      const key = `${style.color}/${background}`;
      const row = pairs.get(key) || { foreground: style.color, background,
        ratio: Number(ratio(style.color, background).toFixed(2)), examples: [] };
      if (row.examples.length < 5) row.examples.push(element.id || element.className || element.tagName);
      pairs.set(key, row);
    }
    const root = getComputedStyle(document.documentElement);
    // Create hidden measurement nodes to resolve hex tokens to computed RGB values.
    const resolve = token => {
      const node = document.createElement('span');
      node.style.color = root.getPropertyValue(token);
      document.body.append(node);
      const value = getComputedStyle(node).color;
      node.remove();
      return value;
    };
    const focus = [ ['--focus', '--panel'], ['--signal', '--screen'], ['--screen', '--signal'] ].map(([foreground, background]) => ({
      foreground, background, ratio: Number(ratio(resolve(foreground), resolve(background)).toFixed(2))
    }));
    return { text: [...pairs.values()].sort((a, b) => a.ratio - b.ratio), focusAndActiveButton: focus,
      method: 'WCAG sRGB relative luminance from computed text colors and nearest opaque ancestor background. Review screenshots to confirm decorative pseudo-elements do not cover text. Inactive controls are identified separately.' };
  });
  await writeFile('docs/site-review/contrast.json', JSON.stringify(contrast, null, 2) + '\n');
  await page.setViewportSize({ width: 320, height: 900 });
  await page.screenshot({ path: 'docs/site-review/mobile-320.webp', type: 'webp', quality: 72, fullPage: true });
  console.log('Saved final export screenshots (1440px / 320px) and computed contrast pairs in docs/site-review/.');
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
