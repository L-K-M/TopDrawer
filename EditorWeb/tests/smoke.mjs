import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { chromium } from 'playwright';

/**
 * Phase 0 smoke test: loads the harness in headless Chromium and verifies the
 * gates that don't need a native host — boot, ready handshake, typing produces
 * one debounced `changed`, theme/mode commands work, and zero cross-origin
 * network requests. Run: `npm run smoke`.
 */
const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
};

const server = createServer(async (req, res) => {
  const urlPath = (req.url ?? '/').split('?')[0];
  const path = normalize(join('.', urlPath === '/' ? '/harness/index.html' : urlPath));

  // This is a dev server on localhost; still, never serve outside the package.
  if (path.startsWith('..')) {
    res.writeHead(403).end('forbidden');
    return;
  }

  try {
    const body = await readFile(path);
    res.writeHead(200, { 'content-type': MIME[extname(path)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch();
const page = await browser.newPage();
const crossOrigin = [];
const pageProblems = [];
page.on('request', (req) => {
  if (!req.url().startsWith(base) && !req.url().startsWith('data:')) crossOrigin.push(req.url());
});
page.on('console', (msg) => {
  if (msg.type() === 'error' || msg.type() === 'warning') pageProblems.push(`console.${msg.type()}: ${msg.text()}`);
});
page.on('pageerror', (error) => pageProblems.push(`pageerror: ${error.message}`));

const failures = [];
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures.push(name);
};

/** Bridge log lines, newest last. The harness renders each message as a div. */
const bridgeLines = () =>
  page.evaluate(() =>
    [...document.querySelectorAll('#bridge-log > div')].map((el) => el.textContent),
  );

async function dumpDiagnostics() {
  console.error('\n--- bridge log ---');
  for (const line of await bridgeLines()) console.error(line.slice(0, 200));
  console.error('--- page problems ---');
  for (const problem of pageProblems) console.error(problem);
  console.error('--- cross-origin requests ---');
  for (const url of crossOrigin) console.error(url);
}

try {
  await page.goto(`${base}/harness/index.html`);
  await page.waitForSelector('.ProseMirror', { timeout: 15000 });
  check('editor boots to rich mode', true);

  await page.waitForFunction(() =>
    [...document.querySelectorAll('#bridge-log > div')].some((el) =>
      el.textContent.includes('"ready"'),
    ),
  );
  check('ready handshake sent', true);

  const initial = await page.locator('.ProseMirror').innerText();
  check('corpus document rendered', initial.includes('Welcome'), initial.slice(0, 40));

  const changedCount = async () =>
    (await bridgeLines()).filter((line) => line.includes('"changed"')).length;

  check('load emits no changed', (await changedCount()) === 0, `${await changedCount()} message(s)`);

  // Type into the surface: exactly one debounced changed message. The debounce
  // plus Playwright's own event dispatch make a fixed sleep racy, so wait for
  // the message and then confirm no further edits produced a second one.
  await page.locator('.ProseMirror').click();
  // Click alone is not guaranteed to leave the contenteditable focused.
  await page.evaluate(() => document.querySelector('.ProseMirror')?.focus());
  await page.keyboard.press('End');
  await page.keyboard.type(' typed');
  try {
    await page.waitForFunction(
      () =>
        [...document.querySelectorAll('#bridge-log > div')].filter((el) =>
          el.textContent.includes('"changed"'),
        ).length >= 1,
      { timeout: 10000 },
    );
  } catch {
    check('typing emits debounced changed', false, 'no changed message within 10s');
  }
  await page.waitForTimeout(500);
  const afterTyping = await changedCount();
  if (afterTyping >= 1) check('typing emits debounced changed', afterTyping === 1, `${afterTyping} message(s)`);

  // Toggle to source mode and back; document must survive.
  await page.click('#mode');
  await page.waitForSelector('.cm-content', { timeout: 5000 });
  const sourceText = await page.locator('.cm-content').innerText();
  check('source mode shows markdown', sourceText.includes('# Welcome'), sourceText.slice(0, 30));
  await page.click('#mode');
  await page.waitForSelector('.ProseMirror', { timeout: 5000 });
  check('mode round-trip back to rich', (await page.locator('.ProseMirror').innerText()).includes('Welcome'));

  // Theme command flips the root attribute.
  await page.click('#theme');
  const theme = await page.evaluate(() => document.documentElement.dataset.tdTheme);
  check('setTheme dark applied', theme === 'dark');

  // Links: an editing click must not launch anything, Cmd/Ctrl-click must hand
  // the URL to the host, and the web view must never navigate (which would
  // destroy the session).
  await page.selectOption('#corpus', 'links');
  await page.click('#replace');
  await page.waitForSelector('#editor a[href]', { timeout: 5000 });
  const openedLinks = async () =>
    (await bridgeLines()).filter((line) => line.includes('"openLink"')).length;

  await page.locator('#editor a[href]').first().click();
  await page.waitForTimeout(300);
  check('plain click does not open a link', (await openedLinks()) === 0);
  check('plain click does not navigate', (await page.evaluate(() => location.pathname)).includes('harness'));

  await page.locator('#editor a[href]').first().click({ modifiers: ['Meta'] });
  await page.waitForTimeout(300);
  check('Cmd-click opens the link externally', (await openedLinks()) === 1);

  // Hostile corpus must render inertly under the strict CSP: no elements built
  // from raw HTML, no image node, and no fetch attempt for the remote image.
  await page.selectOption('#corpus', 'hostile');
  await page.click('#replace');
  await page.waitForTimeout(500);
  const injected = await page.evaluate(() => ({
    script: document.querySelectorAll('#editor script, #editor iframe').length,
    img: document.querySelectorAll('#editor img').length,
    handlers: document.querySelectorAll('#editor [onerror], #editor [onclick]').length,
    text: (document.querySelector('#editor .ProseMirror')?.textContent ?? '').slice(0, 60),
  }));
  check(
    'hostile markup renders inertly',
    injected.script === 0 && injected.img === 0 && injected.handlers === 0,
    JSON.stringify(injected),
  );

  // Offline gate.
  check('zero cross-origin requests', crossOrigin.length === 0, crossOrigin.join(', '));
} catch (error) {
  console.error(`\nSmoke test threw: ${error}`);
  await dumpDiagnostics();
  await browser.close();
  server.close();
  process.exit(1);
}

if (failures.length) {
  await dumpDiagnostics();
  await browser.close();
  server.close();
  console.error(`\n${failures.length} gate(s) failed`);
  process.exit(1);
}

await browser.close();
server.close();
console.log('\nAll smoke gates passed');
