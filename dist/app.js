import { FALLBACK, normalizeCoin, formatUsd, exactUsd } from './coin-data.js';

/** @template {HTMLElement} T @param {string} id @returns {T} */
function element(id) {
  const node = document.getElementById(id);
  if (!node) throw new Error(`Missing site element: ${id}`);
  return /** @type {T} */ (node);
}

const logo = /** @type {HTMLImageElement} */ (element('logo'));
const copy = /** @type {HTMLButtonElement} */ (element('copy'));
const refresh = /** @type {HTMLButtonElement} */ (element('refresh'));
const buy = /** @type {HTMLAnchorElement} */ (element('buy'));
const chart = /** @type {HTMLAnchorElement} */ (element('chart'));
const fallbackLogo = logo.src;
const fallbackAlt = logo.alt;
let logoUrl = '';
/** @type {import('./coin-data.js').Coin|null} */
let latest = null;
let busy = false;
let lastUpdate = '';
let timer = 0;
let copying = false;

/** @param {HTMLAnchorElement} link @param {string} url */
function setLink(link, url) {
  if (url) {
    link.href = url;
    link.removeAttribute('aria-disabled');
  } else {
    link.removeAttribute('href');
    link.setAttribute('aria-disabled', 'true');
  }
}

/** @param {string} text */
function announce(text) { element('announcement').textContent = text; }

/** @param {import('./coin-data.js').Coin} coin */
function paint(coin) {
  document.title = `${coin.name} ($${coin.symbol})`;
  const name = element('name');
  if (coin.name === FALLBACK.name) {
    const swarm = document.createElement('span');
    swarm.textContent = 'Swarm';
    name.replaceChildren(swarm, document.createTextNode(' PEPEPHEREUM'));
  } else name.textContent = coin.name;
  const cursor = document.createElement('span');
  cursor.className = 'cursor'; cursor.setAttribute('aria-hidden', 'true'); cursor.textContent = '_';
  element('ticker').replaceChildren(document.createTextNode(`$${coin.symbol}`), cursor);
  element('buy-label').textContent = `Buy $${coin.symbol}`;
  for (const id of ['chain', 'description-chain', 'how-chain']) element(id).textContent = coin.chainName;
  element('status').textContent = coin.token ? coin.status : (coin.status.toLowerCase() === 'live' ? 'Launching' : coin.status);
  element('status').dataset.state = coin.token && coin.status.toLowerCase() === 'live' ? 'live' : 'pending';
  element('contract').textContent = coin.token || 'launching…';
  copy.disabled = !coin.token || copying;
  setLink(buy, coin.token ? coin.coinUrl : '');
  setLink(chart, coin.token ? coin.chartUrl : '');
  element('action-note').textContent = !coin.token
    ? 'Buy and chart links will appear when the launch is ready.'
    : !coin.coinUrl || !coin.chartUrl
      ? 'Some launch links are not available yet. Try Refresh data.'
      : 'Opens the launchpad or chart. Review the live quote and fees before swapping.';
  for (const [id, value, isPrice] of /** @type {Array<[string, number|null, boolean]>} */ ([
    ['market-cap', coin.market.marketCap, false],
    ['price', coin.market.priceUsd, true],
    ['volume', coin.market.volume24h, false]
  ])) {
    const visible = document.createElement('span');
    visible.dataset.display = '';
    visible.setAttribute('aria-hidden', 'true');
    visible.textContent = formatUsd(value, isPrice);
    const fullValue = document.createElement('span');
    fullValue.className = 'sr-only';
    fullValue.textContent = exactUsd(value);
    element(id).replaceChildren(visible, fullValue);
    element(id).title = exactUsd(value);
  }
  const nextLogo = coin.logo || fallbackLogo;
  if (nextLogo !== logoUrl) {
    logoUrl = nextLogo;
    logo.alt = coin.logo ? `${coin.name} logo` : fallbackAlt;
    logo.src = nextLogo;
  }
}

logo.addEventListener('error', () => {
  if (logo.src !== fallbackLogo) { logo.src = fallbackLogo; logo.alt = fallbackAlt; }
});

async function load(manual = false) {
  if (busy) return;
  busy = true;
  refresh.disabled = true;
  element('feed-state').textContent = 'Refreshing…';
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch('/simd-coin.json', { cache: 'no-store', signal: controller.signal, credentials: 'same-origin' });
    if (!response.ok) throw new Error('Launch feed unavailable');
    const coin = normalizeCoin(await response.json(), window.location.href);
    const firstAddress = !latest?.token && Boolean(coin.token);
    latest = coin;
    paint(coin);
    lastUpdate = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit', timeZone: 'UTC' }).format(new Date());
    element('feed-state').textContent = coin.token ? 'Data connected' : 'Awaiting launch';
    const hasMarket = Object.values(coin.market).some(value => value !== null);
    element('feed-note').textContent = !coin.token
      ? 'The contract is launching. This page checks for launch data every 30 seconds.'
      : hasMarket
        ? `Last updated ${lastUpdate} UTC · Market values in USD · Refreshes every 30 seconds`
        : `Contract available · Market data is not available yet · Checked ${lastUpdate} UTC`;
    if (manual || firstAddress) announce(coin.token ? 'Launch data updated. Contract address available.' : 'Launch data checked. The contract is still launching.');
  } catch {
    element('feed-state').textContent = 'Update unavailable';
    element('feed-note').textContent = latest
      ? `Could not refresh. Showing the last update from ${lastUpdate} UTC. Try Refresh data.`
      : 'Launch data is not available. Try Refresh data. The contract and trading links will appear after deployment.';
    if (manual) announce('Could not load launch data. Try Refresh data.');
  } finally {
    window.clearTimeout(timeout);
    busy = false;
    refresh.disabled = false;
  }
}

copy.addEventListener('click', async () => {
  const token = latest?.token;
  if (!token || copying) return;
  copying = true; copy.disabled = true;
  try {
    if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
    await navigator.clipboard.writeText(token);
    announce('Contract address copied.');
    element('feed-note').textContent = 'Contract address copied. Check the full address on the launchpad before swapping.';
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(element('contract'));
    selection?.removeAllRanges(); selection?.addRange(range);
    const message = 'Could not copy automatically. Select and copy the full contract address shown above.';
    element('feed-note').textContent = message; announce(message);
  } finally { copying = false; copy.disabled = !latest?.token; }
});

refresh.addEventListener('click', () => { void load(true); });
function schedule() {
  window.clearInterval(timer);
  if (!document.hidden) timer = window.setInterval(() => { void load(); }, 30_000);
}
document.addEventListener('visibilitychange', () => {
  schedule();
  if (!document.hidden) void load();
});
window.addEventListener('online', () => { void load(); });
paint(normalizeCoin({}, window.location.href));
void load();
schedule();
