import { cp, mkdir, readdir, rm, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const dist = path.join(root, 'dist');
// Only this generated export is replaced. Source runs directly without this step.
await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
for (const entry of ['index.html', 'styles.css', 'app.js', 'coin-data.js', 'assets']) {
  await cp(path.join(root, 'site', entry), path.join(dist, entry), { recursive: true });
}
async function size(dir) {
  let bytes = 0;
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const filename = path.join(dir, entry.name);
    bytes += entry.isDirectory() ? await size(filename) : (await stat(filename)).size;
  }
  return bytes;
}
console.log(`Static production export: dist/ (${await size(dist)} bytes). No bundler or runtime dependencies.`);
