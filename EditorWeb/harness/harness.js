/**
 * Harness host simulator. Stands in for the native host (WKWebView /
 * WebKitGTK) so the editor bundle can be exercised in a plain browser:
 * loads corpus documents, toggles theme/mode, logs bridge traffic, and counts
 * network requests (the offline gate must stay at zero).
 */

const CORPUS = {
  empty: '',
  welcome:
    '# Welcome\n\n- [ ] Try a task\n- [x] Done task\n\nSome **bold** and *italic* and `code`.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n',
  nested: '- a\n  - b\n    - c\n\n1. one\n2. two\n   - sub\n',
  edge: '> quote with **bold**\n\n---\n\n```js\nconst x = 1;\n```\n\nAutolink https://example.com and [a link](https://example.com "title").\n',
  links: 'A [labelled link](https://example.com/page) and a bare https://example.com URL.\n',
  // `<\/script>` is escaped so the HTML parser does not end the surrounding
  // script element mid-string. The payload must render inertly.
  hostile:
    '<script>alert(1)<\/script>\n\n[xss](javascript:alert(1))\n\n![img](https://evil.example/x.png)\n\n<img src=x onerror="alert(2)">\n',
  crlf: 'line one\r\nline two\r\n- [ ] task\r\n',
  unicode: '# Héllo 世界\n\nעברית וערבית mixed with english text.\n\nEmoji 🍼 in a paragraph.\n',
};

// Offline gate: count only real network schemes, including resources fetched
// before the observer registered (buffered) and under file:// where
// location.origin is "null".
let netCount = 0;
const netCountEl = document.getElementById('net-count');
function countResource(entry) {
  try {
    const { protocol } = new URL(entry.name);
    if (protocol === 'http:' || protocol === 'https:') netCount += 1;
  } catch {
    // Non-URL entry names cannot be network fetches.
  }
  netCountEl.textContent = String(netCount);
}
new PerformanceObserver((list) => list.getEntries().forEach(countResource)).observe({
  type: 'resource',
  buffered: true,
});

const bridgeLog = document.getElementById('bridge-log');
let booted = false;

/**
 * The editor is only ready to accept `initialize` once it says so: a fixed
 * timeout races its asynchronous mount. Called from `log`, so it must never
 * call back into it.
 */
function bootWhenReady(message) {
  if (booted || message?.type !== 'ready') return;
  booted = true;
  document.getElementById('load').click();
}

window.topdrawerHarness = {
  log(direction, message) {
    const line = document.createElement('div');
    line.className = direction;
    line.textContent = `${direction === 'in' ? '→' : '←'} ${JSON.stringify(message)}`;
    bridgeLog.appendChild(line);
    bridgeLog.scrollTop = bridgeLog.scrollHeight;
    if (direction === 'out') bootWhenReady(message);
  },
};

const select = document.getElementById('corpus');
for (const name of Object.keys(CORPUS)) {
  const option = document.createElement('option');
  option.value = name;
  option.textContent = name;
  select.appendChild(option);
}

const markdown = document.getElementById('markdown');
markdown.value = CORPUS.welcome;
select.value = 'welcome';
select.onchange = () => {
  markdown.value = CORPUS[select.value];
};

let revision = 0;
let theme = 'light';
const send = (message) => window.topdrawerEditor.handleMessage(JSON.stringify(message));

document.getElementById('load').onclick = () => {
  booted = true;
  send({
    type: 'initialize',
    markdown: markdown.value,
    theme,
    platform: 'harness',
    revision: (revision += 1),
  });
};
document.getElementById('replace').onclick = () =>
  send({ type: 'replaceDocument', markdown: markdown.value, revision: (revision += 1) });
document.getElementById('theme').onclick = () => {
  theme = theme === 'light' ? 'dark' : 'light';
  send({ type: 'setTheme', theme });
};
document.getElementById('mode').onclick = () => send({ type: 'command', name: 'toggleMode' });
document.getElementById('focus').onclick = () => send({ type: 'focus' });
document.getElementById('undo').onclick = () => send({ type: 'command', name: 'undo' });
document.getElementById('redo').onclick = () => send({ type: 'command', name: 'redo' });
