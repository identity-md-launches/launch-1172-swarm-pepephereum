import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.webp': 'image/webp', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8' };

/** A local preview under /preview/ catches absolute asset path mistakes.
 * No launch data is fabricated; /simd-coin.json returns 404 unless tests intercept it. */
export async function startServer(port = 0) {
  const server = http.createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      if (!pathname.startsWith('/preview/')) { response.writeHead(404).end('Not found'); return; }
      const file = path.resolve(root, pathname.slice('/preview/'.length) || 'index.html');
      if (!file.startsWith(root)) { response.writeHead(403).end('Forbidden'); return; }
      const body = await readFile(file);
      response.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      response.end(body);
    } catch { response.writeHead(404).end('Not found'); }
  });
  await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
  return { server, url: `http://127.0.0.1:${server.address().port}/preview/` };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { server, url } = await startServer(Number(process.argv[2] || 4174));
  console.log(`SPEPE static preview: ${url}\nThe local feed is intentionally unavailable. Press Ctrl+C to stop.`);
  const close = () => server.close(() => process.exit(0));
  process.on('SIGINT', close);
  process.on('SIGTERM', close);
}
