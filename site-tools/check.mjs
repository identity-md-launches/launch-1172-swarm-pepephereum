import { cp, mkdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const scratch = path.join(root, 'test/scratch/site-tools');
const env = { ...process.env, npm_config_cache: path.join(root, 'test/scratch/npm-cache'),
  PLAYWRIGHT_BROWSERS_PATH: path.join(root, 'test/scratch/browsers') };
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, env, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
switch (process.argv[2]) {
  case 'install':
    await mkdir(scratch, { recursive: true });
    for (const file of ['package.json', 'package-lock.json']) {
      await cp(path.join(root, 'site-tools', file), path.join(scratch, file));
    }
    run('npm', ['ci', '--prefix', scratch, '--no-audit', '--no-fund']);
    run(process.execPath, [path.join(scratch, 'node_modules/playwright/cli.js'), 'install', 'chromium']);
    break;
  case 'typecheck':
    run(process.execPath, [path.join(scratch, 'node_modules/typescript/bin/tsc'), '--project', 'site-tools/tsconfig.json']);
    break;
  case 'test':
    run(process.execPath, ['--test', 'site-tools/site.test.mjs']);
    break;
  case 'review':
    run(process.execPath, ['site-tools/review.mjs']);
    break;
  default:
    console.error('Usage: node site-tools/check.mjs install|typecheck|test|review');
    process.exit(1);
}
