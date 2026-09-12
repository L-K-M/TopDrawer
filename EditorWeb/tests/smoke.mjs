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

  // The formatting bar is opt-in. Section 3 covers what it does to the layout
  // once it is on; this only covers the host switching it.
  const barVisibility = async () =>
    harness.page.evaluate(() => {
      const bar = document.querySelector('.milkdown-top-bar');
      return bar ? getComputedStyle(bar).display : 'absent';
    });
  check('harness: formatting bar hidden by default', (await barVisibility()) === 'none');

  const awaitBar = (display) =>
    harness.page
      .waitForFunction(
        (want) => getComputedStyle(document.querySelector('.milkdown-top-bar')).display === want,
        display,
        { timeout: 5000 },
      )
      .catch(() => {});

  // The toggle travels host -> bridge -> DOM, so assert after the transition has
  // landed rather than racing it.
  await harness.page.click('#formatting-bar');
  await awaitBar('flex');
  check('harness: formatting bar shown on request', (await barVisibility()) === 'flex');

  await harness.page.click('#formatting-bar');
  await awaitBar('none');
  check('harness: formatting bar hidden again on request', (await barVisibility()) === 'none');

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
    documentID: 'production-note',
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
  const change = production.ofType('changed')[0];
  // The change must name its document: the host attributes the save by it, because
  // an edit can arrive after the drawer has moved on to another tab.
  check(
    'production: the change names its document',
    change?.documentID === 'production-note',
    JSON.stringify(change ?? null),
  );
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
    documentID: 'production-note',
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
      documentID: 'file-note',
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
    fileMountMs !== null &&
      filePage.ofType('ready').length === 1 &&
      filePage.cspViolations.length === 0 &&
      // A console or page error would otherwise pass while the detail above
      // reported it.
      filePage.problems.length === 0,
    fileDetail,
  );

  // ---------------------------------------------------------------------------
  // Section 3: drawer layout of the shipped page, in a drawer-sized viewport.
  //
  // Both gates guard the same structural rule: `#editor` scrolls, and
  // `.milkdown` inside it must grow with the note. The formatting bar is
  // `position: sticky`, so it can only stay pinned inside its containing block;
  // when `.milkdown` was exactly one drawer tall the bar unpinned and scrolled
  // out of view as soon as the note was longer than that. The harness gate above
  // covers switching the bar on; this one covers the shipped page and the ends of
  // the scroll range. Growing `.milkdown` costs the percentage `min-height` that
  // used to stretch the editable, so the second gate keeps the editable filling a
  // short drawer (a click anywhere in the empty area must land in the editor).
  // ---------------------------------------------------------------------------
  const layout = await openPage('/dist/editor.html', { asHost: true });
  await layout.page.setViewportSize({ width: 520, height: 640 });
  await layout.send({
    type: 'initialize',
    markdown: ['# Long note', ...Array.from({ length: 200 }, (_, index) => `Paragraph ${index + 1}.`)].join('\n\n'),
    theme: 'light',
    platform: 'linux',
    documentID: 'layout-note',
    revision: 1,
  });
  await layout.page.waitForSelector('.ProseMirror', { timeout: 15000 });
  await layout.send({ type: 'setFormattingBar', formattingBar: 'visible' });
  await layout.page.waitForFunction(
    () => {
      const bar = document.querySelector('.milkdown-top-bar');
      return bar !== null && getComputedStyle(bar).display !== 'none';
    },
    null,
    { timeout: 5000 },
  );

  const barOffsets = await layout.page.evaluate(() => {
    const scroller = document.querySelector('#editor');
    const bar = document.querySelector('.milkdown-top-bar');
    const scrollportTop = scroller.getBoundingClientRect().top;
    const max = scroller.scrollHeight - scroller.clientHeight;
    // One drawer height is where the old layout let go; the rest covers the
    // whole range, including the very bottom.
    return [0, scroller.clientHeight, Math.round(max / 2), max].map((offset) => {
      scroller.scrollTop = offset;
      return Math.round(bar.getBoundingClientRect().top - scrollportTop);
    });
  });
  check(
    'production: the formatting bar stays pinned at every scroll offset',
    barOffsets.every((offset) => offset === 0),
    `bar top at 0/one-drawer/half/end: ${barOffsets.join(', ')}`,
  );

  await layout.send({ type: 'replaceDocument', markdown: '# Short note\n', revision: 2 });
  await layout.page.waitForFunction(
    () => document.querySelector('.ProseMirror')?.textContent?.includes('Short note'),
    null,
    { timeout: 5000 },
  );
  const shortNote = await layout.page.evaluate(() => {
    const scroller = document.querySelector('#editor');
    const editable = document.querySelector('.ProseMirror');
    return {
      gapBelowEditable: Math.round(
        scroller.getBoundingClientRect().bottom - editable.getBoundingClientRect().bottom,
      ),
      overflow: scroller.scrollHeight - scroller.clientHeight,
    };
  });
  check(
    'production: a short note still fills the drawer, without scrolling it',
    shortNote.gapBelowEditable === 0 && shortNote.overflow === 0,
    JSON.stringify(shortNote),
  );

  // A notes drawer floors at `DrawerMetrics.notesSize`, where the bar wraps to
  // several rows. That is the tallest the sticky item gets and the hardest case
  // for its containing block.
  await layout.page.setViewportSize({ width: 288, height: 400 });
  await layout.send({
    type: 'replaceDocument',
    markdown: ['# Long note', ...Array.from({ length: 200 }, (_, index) => `Paragraph ${index + 1}.`)].join('\n\n'),
    revision: 3,
  });
  await layout.page.waitForFunction(
    () => document.querySelector('.ProseMirror')?.textContent?.includes('Paragraph 200'),
    null,
    { timeout: 5000 },
  );
  const narrowOffsets = await layout.page.evaluate(() => {
    const scroller = document.querySelector('#editor');
    const bar = document.querySelector('.milkdown-top-bar');
    const scrollportTop = scroller.getBoundingClientRect().top;
    const max = scroller.scrollHeight - scroller.clientHeight;
    return [0, scroller.clientHeight, Math.round(max / 2), max].map((offset) => {
      scroller.scrollTop = offset;
      return Math.round(bar.getBoundingClientRect().top - scrollportTop);
    });
  });
  check(
    'production: the wrapped formatting bar stays pinned in a minimum-size drawer',
    narrowOffsets.every((offset) => offset === 0),
    `bar top at 0/one-drawer/half/end: ${narrowOffsets.join(', ')}`,
  );

  // Nothing scrolls the caret with the pinned bar in mind unless it is told, and
  // plain cursor movement is the browser's own scroll, which consults only the
  // scrollport's `scroll-padding-top`. Arrowing upwards used to park the caret
  // behind the bar, fully hidden.
  await layout.page.setViewportSize({ width: 520, height: 640 });
  await layout.page.evaluate(() => {
    document.querySelector('#editor').scrollTop = Number.MAX_SAFE_INTEGER;
  });
  await layout.page.click('.ProseMirror p:nth-last-of-type(3)');
  // Null until something is actually measured: a run where the selection never
  // yields a rect must fail rather than pass on an empty maximum.
  let worstOverlap = null;
  for (let press = 0; press < 40; press += 1) {
    await layout.page.keyboard.press('ArrowUp');
    const overlap = await layout.page.evaluate(() => {
      const selection = window.getSelection();
      const rects = selection?.rangeCount ? selection.getRangeAt(0).getClientRects() : [];
      if (!rects.length) return null;
      const bar = document.querySelector('.milkdown-top-bar').getBoundingClientRect();
      return Math.round(bar.bottom - rects[0].top);
    });
    if (overlap !== null) worstOverlap = Math.max(worstOverlap ?? Number.NEGATIVE_INFINITY, overlap);
  }
  check(
    'production: arrowing upwards keeps the caret clear of the pinned bar',
    worstOverlap !== null && worstOverlap <= 0,
    worstOverlap === null ? 'no caret rect was ever measured' : `worst overlap ${worstOverlap}px`,
  );

  // Crepe's reset strips every focus ring, and its `button:focus` rule outranks a
  // plain `:focus-visible` override, so the bar's buttons had none at all
  // (WCAG 2.4.7). The editing surface stays ring-free: the caret is its indicator.
  const focusRings = [];
  // Out of the editable first: ProseMirror handles Tab itself, so tabbing from
  // inside the document never reaches the bar.
  await layout.page.evaluate(() => document.activeElement?.blur());
  await layout.page.keyboard.press('Tab');
  for (let stop = 0; stop < 4; stop += 1) {
    focusRings.push(
      await layout.page.evaluate(() => {
        const style = getComputedStyle(document.activeElement);
        return {
          inBar: !!document.activeElement.closest('.milkdown-top-bar'),
          ring: `${style.outlineWidth} ${style.outlineStyle}`,
        };
      }),
    );
    await layout.page.keyboard.press('Tab');
  }
  const barStops = focusRings.filter((stop) => stop.inBar);
  check(
    'production: keyboard focus is visible on the formatting bar',
    barStops.length > 0 && barStops.every((stop) => stop.ring === '2px solid'),
    barStops.length ? barStops.map((stop) => stop.ring).join(', ') : 'no bar control was tabbable',
  );

  // Switching the bar back off has to take the inset with it, or a drawer with no
  // bar would scroll as if one were there.
  await layout.send({ type: 'setFormattingBar', formattingBar: 'hidden' });
  await layout.page.waitForFunction(
    () => getComputedStyle(document.querySelector('#editor')).scrollPaddingTop === '0px',
    null,
    { timeout: 5000 },
  ).catch(() => {});
  const insetWhenHidden = await layout.page.evaluate(
    () => getComputedStyle(document.querySelector('#editor')).scrollPaddingTop,
  );
  check(
    'production: hiding the formatting bar clears the caret inset',
    insetWhenHidden === '0px',
    insetWhenHidden,
  );
  await layout.send({ type: 'setFormattingBar', formattingBar: 'visible' });

  // The dark palette is only legible over the page's own opaque canvas: a page
  // that paints nothing gets the embedder's opaque base, which resolves light.
  // Opacity is asserted separately because a transparent canvas reports
  // `rgba(0, 0, 0, 0)`, which would otherwise score as black and pass. Both
  // modes share `#editor`, so both are checked.
  const relativeLuminance = (color) => {
    const [r, g, b] = color
      .match(/[\d.]+/g)
      .slice(0, 3)
      .map((value) => {
        const channel = value / 255;
        return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
      });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const contrastRatio = (a, b) => {
    const [high, low] = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x);
    return (high + 0.05) / (low + 0.05);
  };
  const isOpaque = (color) => !/^rgba\(/.test(color) || /,\s*1\s*\)$/.test(color);

  await layout.send({ type: 'setTheme', theme: 'dark' });
  for (const mode of ['rich', 'source']) {
    if (mode === 'source') await layout.send({ type: 'command', name: 'toggleMode' });
    const selector = mode === 'source' ? '.cm-content' : '.ProseMirror';
    await layout.page.waitForSelector(selector, { timeout: 15000 });
    const paint = await layout.page.evaluate((sel) => {
      const root = getComputedStyle(document.documentElement);
      return {
        canvas: root.backgroundColor,
        scheme: root.colorScheme,
        text: getComputedStyle(document.querySelector(sel)).color,
      };
    }, selector);
    check(
      `production: ${mode} mode declares a dark color-scheme`,
      paint.scheme === 'dark',
      paint.scheme,
    );
    check(
      `production: ${mode} mode dark text is legible on an opaque canvas`,
      isOpaque(paint.canvas) && contrastRatio(paint.text, paint.canvas) >= 4.5,
      `${contrastRatio(paint.text, paint.canvas).toFixed(1)}:1 (${paint.text} on ${paint.canvas})`,
    );
  }

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
