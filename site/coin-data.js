// Shared, DOM-independent validation for the same-origin launch feed.
/** @typedef {{ marketCap: number|null, priceUsd: number|null, volume24h: number|null }} Market */
/** @typedef {{ name: string, symbol: string, token: string, chainName: string, coinUrl: string, chartUrl: string, logo: string, status: string, market: Market }} Coin */

export const FALLBACK = Object.freeze({ name: 'Swarm PEPEPHEREUM', symbol: 'SPEPE', chainName: 'Robinhood Chain' });

/** @param {unknown} value @param {string} fallback @param {number} maxLength */
function label(value, fallback, maxLength) {
  return typeof value === 'string' && value.trim() && value.trim().length <= maxLength
    ? value.trim() : fallback;
}

/** Accept HTTPS URLs or same-origin relative URLs. Never execute feed-provided schemes.
 * @param {unknown} value @param {string} base */
export function safeUrl(value, base) {
  if (typeof value !== 'string' || !value.trim()) return '';
  try {
    const url = new URL(value, base);
    const origin = new URL(base);
    if (url.username || url.password) return '';
    if (url.protocol === 'https:' || (url.protocol === 'http:' && url.origin === origin.origin)) return url.href;
  } catch { /* Invalid URLs leave the corresponding action unavailable. */ }
  return '';
}

/** @param {unknown} value */
export function marketNumber(value) {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  if (typeof value === 'string' && (!value.trim() || !/^\d+(\.\d+)?([eE][+-]?\d+)?$/.test(value.trim()))) return null;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
}

/** Validate data at the boundary; invalid fields never become HTML or trading URLs.
 * @param {unknown} input @param {string} base @returns {Coin} */
export function normalizeCoin(input, base) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid launch data');
  const c = /** @type {Record<string, unknown>} */ (input);
  const market = c.market && typeof c.market === 'object' && !Array.isArray(c.market)
    ? /** @type {Record<string, unknown>} */ (c.market) : {};
  const token = typeof c.token === 'string' && /^0x[\da-f]{40}$/i.test(c.token) && !/^0x0{40}$/i.test(c.token) ? c.token : '';
  return {
    name: label(c.name, FALLBACK.name, 120),
    symbol: label(c.symbol, FALLBACK.symbol, 32).replace(/^\$/, ''),
    chainName: label(c.chainName, FALLBACK.chainName, 96),
    status: label(c.status, token ? 'Deployed' : 'Launching', 64),
    token,
    coinUrl: safeUrl(c.coinUrl, base),
    chartUrl: safeUrl(c.chartUrl, base),
    logo: safeUrl(c.logo, base),
    market: {
      marketCap: marketNumber(market.marketCap),
      priceUsd: marketNumber(market.priceUsd),
      volume24h: marketNumber(market.volume24h)
    }
  };
}

/** @param {number|null} value @param {boolean} [price] */
export function formatUsd(value, price = false) {
  if (value === null) return '—';
  if (value === 0) return '$0.00';
  if (value < 0.000001) return `$${value.toExponential(2)}`;
  return new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD',
    ...(price
      ? { maximumSignificantDigits: 5 }
      : value >= 1_000_000
        ? { notation: 'compact', maximumFractionDigits: 2 }
        : { maximumFractionDigits: 2, minimumFractionDigits: 2 })
  }).format(value);
}

/** Complete value is exposed to assistive technology and on hover.
 * @param {number|null} value */
export function exactUsd(value) {
  return value === null ? 'Not available' : `${value.toLocaleString('en-US', { maximumSignificantDigits: 16 })} US dollars`;
}
