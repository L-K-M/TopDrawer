import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { chromium } from 'playwright';

/**
 * Phase 0 gates that need a real browser engine, but not a native host.
 *
 * Section 1 drives the harness (a simulated host with controls and a log).
 * Section 2 loads the shipped page in `dist/` the way a host application loads
 * it: install a message recorder before the bundle runs, then talk to it only
 * through the bridge. Section 2 also records the timings and memory numbers the
 * plan asks to be published rather than guessed.
 *
 * Run: `npm run smoke`.
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
// Loopback only: this dev server must not be reachable from the network.
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch({
  args: [
    // Without this Chromium quantizes performance.memory, which would make the
    // heap numbers below meaningless.
    '--enable-precise-memory-info',
    // Lets the heap be sampled after a forced collection; otherwise the figure
    // is whatever garbage happened not to be collected yet.
    '--js-flags=--expose-gc',
  ],
});
const failures = [];
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures.push(name);
};

/**
 * A page that records bridge traffic, CSP violations and network activity.
 *
 * `target` is a path under the dev server, or an absolute URL (used for the
 * file:// load below).
 *
 * `asHost` installs the `window.webkit.messageHandlers.topdrawer` transport that
 * WKWebView and WebKitGTK provide, so the shipped page is exercised through the
 * transport the real host uses rather than the harness fallback.
 */
async function openPage(target, { asHost = false } = {}) {
  const url = /^[a-z]+:\/\//i.test(target) ? target : `${base}${target}`;
  const page = await browser.newPage();
  const state = { crossOrigin: [], problems: [], messages: [], cspViolations: [], heap: null };

  await page.addInitScript((useWebkit) => {
    window.__editorMessages = [];
    window.__cspViolations = [];
    document.addEventListener('securitypolicyviolation', (event) => {
      window.__cspViolations.push(`${event.violatedDirective} ${event.blockedURI}`);
    });

    if (useWebkit) {
      window.webkit = {
        messageHandlers: {
          topdrawer: {
            postMessage: (message) => window.__editorMessages.push(message),
          },
        },
      };
      return;
    }

    // The harness page is its own host and logs traffic itself.
    window.topdrawerHarness = {
      log(direction, message) {
        if (direction === 'out') window.__editorMessages.push(message);
      },
    };
  }, asHost);

  page.on('request', (req) => {
    if (!req.url().startsWith(base) && !req.url().startsWith('data:')) state.crossOrigin.push(req.url());
  });
  page.on('console', (msg) => {
    if (msg.type() === 'error' || msg.type() === 'warning') state.problems.push(`console.${msg.type()}: ${msg.text()}`);
  });
  page.on('pageerror', (error) => state.problems.push(`pageerror: ${error.message}`));

  await page.goto(url);
  state.page = page;

  state.read = async () => {
    state.messages = await page.evaluate(() => window.__editorMessages ?? []);
    state.cspViolations = await page.evaluate(() => window.__cspViolations ?? []);
    state.heap = await page.evaluate(async () => {
      window.gc?.();
      // Let the collection settle before sampling.
      await new Promise((r) => requestAnimationFrame(() => r(null)));
      return performance.memory?.usedJSHeapSize ?? null;
    });
    return state;
  };
  state.ofType = (type) => state.messages.filter((m) => m.type === type);
  state.log = async () =>
    page.evaluate(() =>
      [...document.querySelectorAll('#bridge-log > div')].map((el) => el.textContent),
    );

  /** Sends a host -> editor message through the bridge, as the host would. */
  state.send = (message) =>
    page.evaluate((m) => window.topdrawerEditor.handleMessage(JSON.stringify(m)), message);

  /**
   * Times a mount on the page's own clock, not Node's: a `Date.now()` span
   * around `page.goto`/`send` includes IPC and Playwright overhead.
   */
  state.measureMount = (message) =>
    page.evaluate(async (m) => {
      const start = performance.now();
      window.topdrawerEditor.handleMessage(JSON.stringify(m));
      await new Promise((resolve) => {
        const poll = () =>
          document.querySelector('.ProseMirror') ? resolve() : requestAnimationFrame(poll);
        poll();
      });
      return performance.now() - start;
    }, message);

  /** Page load as the browser reports it (Navigation Timing). */
  state.pageLoadMs = () =>
    page.evaluate(() => {
      const entry = performance.getEntriesByType('navigation')[0];
      return entry ? entry.loadEventEnd - entry.startTime : null;
    });

  return state;
}

async function dumpDiagnostics(state, label) {
  console.error(`\n--- ${label}: editor -> host ---`);
  for (const message of await state.read().then((s) => s.messages)) {
    console.error(JSON.stringify(message).slice(0, 200));
  }
  console.error('--- page problems ---');
  for (const problem of state.problems) console.error(problem);
  console.error('--- cross-origin requests ---');
  for (const url of state.crossOrigin) console.error(url);
  console.error('--- CSP violations ---');
  for (const violation of state.cspViolations) console.error(violation);
}

try {
  // ---------------------------------------------------------------------------
  // Section 1: the harness, which exposes controls and a visible bridge log.
  // ---------------------------------------------------------------------------
  const harness = await openPage('/harness/index.html');
  await harness.page.waitForSelector('.ProseMirror', { timeout: 15000 });
  check('harness: editor boots to rich mode', true);

  await harness.page.waitForFunction(() =>
    [...document.querySelectorAll('#bridge-log > div')].some((el) => el.textContent.includes('"ready"')),
  );
  check('harness: ready handshake sent', true);

  const initial = await harness.page.locator('.ProseMirror').innerText();
  check('harness: corpus document rendered', initial.includes('Welcome'), initial.slice(0, 40));

  const harnessChanged = async () =>
    (await harness.log()).filter((line) => line.includes('"changed"')).length;
  const changedOnLoad = await harnessChanged();
  check('harness: load emits no changed', changedOnLoad === 0, `${changedOnLoad} message(s)`);

  // Typing must reach the host as one debounced change. The debounce plus
  // Playwright's own dispatch make a fixed sleep racy, so wait for the message
  // and then confirm a settle period produced no second one.
  await harness.page.locator('.ProseMirror').click();
  // Click alone is not guaranteed to leave the contenteditable focused.
  await harness.page.evaluate(() => document.querySelector('.ProseMirror')?.focus());
  await harness.page.keyboard.press('End');
  await harness.page.keyboard.type(' typed');
  try {
    await harness.page.waitForFunction(
      () =>
        [...document.querySelectorAll('#bridge-log > div')].filter((el) =>
          el.textContent.includes('"changed"'),
        ).length >= 1,
      { timeout: 10000 },
    );
  } catch {
    check('harness: typing emits debounced changed', false, 'no changed message within 10s');
  }
  await harness.page.waitForTimeout(500);
  const afterTyping = await harnessChanged();
  if (afterTyping >= 1) check('harness: typing emits debounced changed', afterTyping === 1, `${afterTyping} message(s)`);

  await harness.page.click('#mode');
  await harness.page.waitForSelector('.cm-content', { timeout: 5000 });
  const sourceText = await harness.page.locator('.cm-content').innerText();
  check('harness: source mode shows markdown', sourceText.includes('# Welcome'), sourceText.slice(0, 30));

  await harness.page.click('#mode');
  await harness.page.waitForSelector('.ProseMirror', { timeout: 5000 });
  check(
    'harness: mode round-trip back to rich',
    (await harness.page.locator('.ProseMirror').innerText()).includes('Welcome'),
  );

  await harness.page.click('#theme');
  const theme = await harness.page.evaluate(() => document.documentElement.dataset.tdTheme);
  check('harness: setTheme dark applied', theme === 'dark');

  // Links: an editing click must not launch anything, Cmd/Ctrl-click must hand
  // the URL to the host, and the web view must never navigate.
  await harness.page.selectOption('#corpus', 'links');
  await harness.page.click('#replace');
  await harness.page.waitForSelector('#editor a[href]', { timeout: 5000 });
  const openedLinks = async () => (await harness.log()).filter((line) => line.includes('"openLink"')).length;

  await harness.page.locator('#editor a[href]').first().click();
  await harness.page.waitForTimeout(300);
  const linksAfterPlainClick = await openedLinks();
  check(
    'harness: plain click does not open a link',
    linksAfterPlainClick === 0,
    `${linksAfterPlainClick} openLink message(s)`,
  );
  check(
    'harness: plain click does not navigate',
    (await harness.page.evaluate(() => location.pathname)).includes('harness'),
  );

  // Control rather than Meta: Playwright's Meta modifier is a no-op on Linux,
  // where the handler's ctrlKey branch is the one that fires.
  await harness.page.locator('#editor a[href]').first().click({ modifiers: ['Control'] });
  await harness.page.waitForTimeout(300);
  const linksAfterCtrlClick = await openedLinks();
  check(
    'harness: Ctrl-click opens the link externally',
    linksAfterCtrlClick === 1,
    `${linksAfterCtrlClick} openLink message(s)`,
  );

  await harness.page.selectOption('#corpus', 'hostile');
  await harness.page.click('#replace');
  await harness.page.waitForTimeout(500);
  const injected = await harness.page.evaluate(() => ({
    script: document.querySelectorAll('#editor script, #editor iframe').length,
    img: document.querySelectorAll('#editor img').length,
    handlers: document.querySelectorAll('#editor [onerror], #editor [onclick]').length,
    text: document.querySelector('#editor .ProseMirror')?.textContent ?? '',
  }));
  check(
    'harness: hostile markup renders inertly',
    injected.script === 0 &&
      injected.img === 0 &&
      injected.handlers === 0 &&
      injected.text.includes('alert(1)') &&
      injected.text.includes('evil.example'),
    JSON.stringify({ ...injected, text: injected.text.slice(0, 60) }),
  );

  await harness.read();
  check('harness: zero cross-origin requests', harness.crossOrigin.length === 0, harness.crossOrigin.join(', '));
  check(
    'harness: no CSP violations',
    harness.cspViolations.length === 0,
    harness.cspViolations.join(', '),
  );

  // ---------------------------------------------------------------------------
  // Section 2: the shipped page, loaded the way a host loads it.
  // ---------------------------------------------------------------------------
  const production = await openPage('/dist/editor.html', { asHost: true });
  const pageLoadMs = await production.pageLoadMs();
  const mountMs = await production.measureMount({
    type: 'initialize',
    markdown: '# Note\n\ntyped text\n',
    theme: 'light',
    platform: 'linux',
    revision: 1,
  });

  await production.read();
  check('production: ready handshake received by host', production.ofType('ready').length === 1);
  check('production: document mounted', (await production.page.locator('.ProseMirror').innerText()).includes('Note'));

  await production.page.locator('.ProseMirror').click();
  await production.page.evaluate(() => document.querySelector('.ProseMirror')?.focus());
  await production.page.keyboard.type('!');
  await production.page.waitForTimeout(600);
  await production.read();
  check(
    'production: typing reaches the host',
    production.ofType('changed').length === 1,
    `${production.ofType('changed').length} changed message(s)`,
  );

  // The page's stricter CSP must not break the editor (fonts, styles, workers).
  check(
    'production: no CSP violations',
    production.cspViolations.length === 0,
    production.cspViolations.join(', '),
  );
  check(
    'production: zero cross-origin requests',
    production.crossOrigin.length === 0,
    production.crossOrigin.join(', '),
  );

  // Warm reopen: assets are cached, so this is what a drawer reopen costs.
  await production.page.reload();
  const warmMs = await production.measureMount({
    type: 'initialize',
    markdown: '# Note\n',
    theme: 'light',
    platform: 'linux',
    revision: 1,
  });

  // Repeated open/close must not grow the heap: the host creates and destroys
  // the editor on every drawer open and mode switch.
  await production.read();
  const heapBefore = production.heap;
  for (let revision = 2; revision <= 11; revision += 1) {
    await production.send({
      type: 'replaceDocument',
      markdown: `# Note\n\nrevision ${revision}\n`,
      revision,
    });
    await production.page.waitForFunction(
      (n) => document.querySelector('.ProseMirror')?.textContent?.includes(`revision ${n}`),
      revision,
      { timeout: 5000 },
    );
  }
  await production.read();
  const heapAfter = production.heap;

  console.log('\nmeasurements (headless Chromium over http on a CI runner)');
  console.log(`  page load (Navigation Timing): ${pageLoadMs === null ? 'unavailable' : `${Math.round(pageLoadMs)} ms`}`);
  console.log(`  mount after initialize:        ${mountMs.toFixed(0)} ms (page clock)`);
  console.log(`  warm reopen (reload + init):   ${warmMs.toFixed(0)} ms (page clock)`);
  if (heapBefore !== null && heapAfter !== null) {
    const growthKb = (heapAfter - heapBefore) / 1024;
    console.log(
      `  heap after 10 document swaps:   ${(heapAfter / 1048576).toFixed(1)} MiB (${growthKb >= 0 ? '+' : ''}${growthKb.toFixed(0)} KiB vs after the first mount, both sampled after a forced GC)`,
    );
    check(
      'production: repeated document swaps do not grow the heap unboundedly',
      // Growth only; a shrinking heap is not a leak.
      heapAfter - heapBefore < 8 * 1048576,
      `${((heapAfter - heapBefore) / 1048576).toFixed(1)} MiB growth across 10 swaps`,
    );
  } else {
    console.log('  heap: unavailable in this engine, not measured');
  }

  // How a host loads the page: file URL with read access scoped to dist/, or a
  // custom scheme. Worth gating because a CSP of `script-src 'self'` depends on
  // the document having an origin that matches its own assets, and file://
  // documents have an opaque one. Measured in Chromium this works, so the
  // shipping question is whether WKWebView agrees (see README).
  const filePage = await openPage(`file://${process.cwd()}/dist/editor.html`, { asHost: true });
  await filePage.page.waitForTimeout(300);
  await filePage.read();
  let fileMountMs = null;
  try {
    fileMountMs = await filePage.measureMount({
      type: 'initialize',
      markdown: '# Note\n',
      theme: 'light',
      platform: 'macos',
      revision: 1,
    });
  } catch {
    fileMountMs = null;
  }
  console.log('\nfile:// load (a host may load the page this way)');
  console.log(`  mounted:            ${fileMountMs === null ? 'no' : `${fileMountMs.toFixed(0)} ms`}`);
  console.log(`  ready handshake:    ${filePage.ofType('ready').length === 1 ? 'received' : 'MISSING'}`);
  console.log(`  CSP violations:     ${filePage.cspViolations.length === 0 ? 'none' : filePage.cspViolations.join(', ')}`);
  if (filePage.problems.length > 0) console.log(`  page problems:      ${filePage.problems.join(' | ')}`);

  const fileDetail =
    [
      fileMountMs === null ? 'did not mount' : null,
      filePage.ofType('ready').length === 1 ? null : 'no ready handshake',
      ...filePage.cspViolations,
      ...filePage.problems,
    ]
      .filter(Boolean)
      .join(' | ') || 'unknown reason';

  check(
    'production: file:// load mounts with the strict CSP',
    fileMountMs !== null && filePage.ofType('ready').length === 1 && filePage.cspViolations.length === 0,
    fileDetail,
  );

  if (failures.length) await dumpDiagnostics(harness, 'harness');
} catch (error) {
  console.error(`\nSmoke test threw: ${error}`);
  await browser.close();
  server.close();
  process.exit(1);
}

await browser.close();
server.close();

if (failures.length) {
  console.error(`\n${failures.length} gate(s) failed`);
  process.exit(1);
}
console.log('\nAll smoke gates passed');
