/**
 * Compatibility corpus for the spike gates (see
 * docs/markdown-editor-improvement-plan.md §Markdown compatibility and data
 * safety). Each fixture states the expected rich-mode round-trip behavior:
 *
 * - 'exact'      getMarkdown() after plain load returns the input byte-for-byte
 * - 'normalized' serialize differs in formatting but stays semantically equal
 *                and reaches a stable fixpoint (the safety property: document
 *                content rich mode cannot render is kept as literal text
 *                rather than dropped, which the escaping above causes)
 *
 * The point of recording expectations per fixture is the spike's support
 * table: any regression in this table is a data-safety finding.
 */
export interface CorpusFixture {
  name: string;
  input: string;
  expect: 'exact' | 'normalized';
}

export const CORPUS: CorpusFixture[] = [
  {
    name: 'empty',
    input: '',
    expect: 'exact',
  },
  {
    name: 'welcome-note-constructs',
    // remark serializes task/bullet lists with '*' markers, so '- [ ]' becomes
    // '* [ ]' on the first real edit. Semantically identical.
    input: [
      '# Welcome',
      '',
      '- [ ] Try a task',
      '- [x] Done task',
      '',
      'Some **bold** and *italic* and `code`.',
      '',
      '| A | B |',
      '|---|---|',
      '| 1 | 2 |',
      '',
    ].join('\n'),
    expect: 'normalized',
  },
  {
    // remark emits '*' bullets; input '-' bullets normalize on first edit.
    name: 'nested-lists',
    input: '- a\n  - b\n    - c\n\n1. one\n2. two\n   - sub\n',
    expect: 'normalized',
  },
  {
    // remark emits '***' for thematic breaks; '---' normalizes on first edit.
    name: 'quote-hr-fence',
    input: '> quote with **bold**\n\n---\n\n```js\nconst x = 1;\n```\n',
    expect: 'normalized',
  },
  {
    // remark emits '<url>' autolink form; bare URLs normalize on first edit.
    name: 'links',
    input: 'Autolink https://example.com and [a link](https://example.com "title").\n',
    expect: 'normalized',
  },
  {
    name: 'crlf-endings',
    input: 'line one\r\nline two\r\n- [ ] task\r\n',
    expect: 'normalized',
  },
  {
    name: 'unicode-bidi',
    input: '# Héllo 世界\n\nעברית וערבית mixed with english text.\n\nEmoji 🍼 in a paragraph.\n',
    expect: 'exact',
  },
  {
    name: 'emphasis-combos',
    input: '***bold-italic*** ~~strike~~ **bold _inner italic_**\n',
    expect: 'exact',
  },
  {
    // Unnecessary escapes are dropped (\- stays literal '-' as plain text).
    name: 'escaped-punctuation',
    input: 'Not a list: \\- item, not a heading: \\# nope\n',
    expect: 'normalized',
  },
  {
    // Would-be syntax that never parsed gets re-escaped on serialize
    // ('**bold without end' -> '\\*\\*bold without end'). Semantically equal.
    name: 'malformed-unclosed',
    input: '**bold without end\n\n- [ task with no bracket\n',
    expect: 'normalized',
  },
  {
    // Raw HTML is never rendered and never becomes DOM: it is kept as literal
    // text, so remark escapes it ('<div>' -> '\<div>') on the first real edit.
    // Content is preserved; a byte-exact inert node view is Phase 2 work.
    name: 'raw-html',
    input: 'Before\n\n<div class="note">raw html block</div>\n\nAfter\n',
    expect: 'normalized',
  },
  {
    // Reference-style images are `imageReference` nodes, not `image`, and a
    // missing definition leaves them unresolved: both forms must still be kept
    // out of the DOM.
    name: 'reference-image',
    input: '![alt][pic]\n\n[pic]: https://evil.example/y.png\n\n![dangling][nope]\n',
    expect: 'normalized',
  },
  {
    // Payloads that must render inertly: no DOM element, no attribute handler,
    // no javascript: navigation, no image fetch. Covered by the hostile test.
    name: 'malicious-payloads',
    input:
      '<script>alert(1)</script>\n\n[xss](javascript:alert(1))\n\n![img](https://evil.example/x.png)\n\n<img src=x onerror="alert(2)">\n',
    expect: 'normalized',
  },
  {
    name: 'reference-link',
    input: '[ref link][1]\n\n[1]: https://example.com/page\n',
    expect: 'normalized',
  },
  {
    name: 'hard-break',
    input: 'line one  \nline two\n',
    expect: 'normalized',
  },
  {
    name: 'footnote',
    input: 'Text with note.[^1]\n\n[^1]: The footnote.\n',
    expect: 'normalized',
  },
];
