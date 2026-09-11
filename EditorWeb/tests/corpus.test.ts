// @vitest-environment happy-dom
import { describe, expect, it, vi } from 'vitest';
import { RichEditor } from '../src/editor';
import { CORPUS } from './corpus';

/**
 * Round-trip gates against the real Crepe build running in happy-dom:
 *
 * 1. Loading a document never fires onChange, even though Crepe applies its
 *    parsed default value in a later transaction (remark normalizes '-'
 *    bullets to '*' and '---' to '***'). The wait below must therefore be
 *    generous: a 50 ms window missed exactly this bug.
 * 2. getMarkdown() round-trips the supported corpus per the expectation table.
 * 3. Hostile markup renders inertly (no script/img elements reach the DOM).
 *
 * The positive path (a real edit emits exactly one debounced `changed`) needs a
 * real browser engine and lives in tests/smoke.mjs.
 */
const SETTLE_MS = 400;

async function mount(input: string, onChange: () => void = () => {}) {
  const root = document.createElement('div');
  document.body.appendChild(root);
  const editor = await RichEditor.mount(root, {
    markdown: input,
    placeholder: 'Write a note…',
    onChange,
    onOpenLink: () => {},
  });
  return { root, editor };
}

describe('rich mode corpus', () => {
  for (const fixture of CORPUS) {
    it(`loads without emitting changes: ${fixture.name}`, async () => {
      const onChange = vi.fn();
      const { root, editor } = await mount(fixture.input, onChange);

      await new Promise((r) => setTimeout(r, SETTLE_MS));
      expect(onChange, 'load must not emit a local change').not.toHaveBeenCalled();

      await editor.destroy();
      root.remove();
    });
  }

  for (const fixture of CORPUS.filter((f) => f.expect === 'exact')) {
    it(`round-trips exactly: ${fixture.name}`, async () => {
      const { root, editor } = await mount(fixture.input);
      expect(editor.getMarkdown()).toBe(fixture.input);
      await editor.destroy();
      root.remove();
    });
  }

  for (const fixture of CORPUS.filter((f) => f.expect === 'normalized')) {
    it(`normalizes to a stable fixpoint: ${fixture.name}`, async () => {
      // Semantics must survive even when bytes don't. A first real edit may
      // normalize the source (remark's serialization, and escaping for content
      // rich mode keeps as literal text), so the safety property is
      // convergence: repeated round-trips must stop changing the document
      // rather than drifting.
      const seen: string[] = [];
      let current = fixture.input;
      for (let pass = 0; pass < 4; pass += 1) {
        const { root, editor } = await mount(current);
        current = editor.getMarkdown();
        await editor.destroy();
        root.remove();
        if (seen.length > 0 && seen[seen.length - 1] === current) return;
        seen.push(current);
      }
      throw new Error(`did not converge after 4 passes: ${JSON.stringify(seen)}`);
    });
  }

  it('mounts a ProseMirror surface and returns loaded markdown unchanged', async () => {
    const { root, editor } = await mount('start\n');
    expect(root.querySelector('.ProseMirror')).toBeTruthy();
    expect(editor.getMarkdown()).toBe('start\n');
    await editor.destroy();
    root.remove();
  });

  it('renders hostile markdown inertly', async () => {
    const hostile = CORPUS.find((f) => f.name === 'raw-html' || f.name === 'malicious-payloads');
    expect(hostile, 'corpus needs a hostile fixture').toBeTruthy();
    const { root, editor } = await mount(hostile!.input);
    await new Promise((r) => setTimeout(r, 30));

    expect(root.querySelector('script')).toBeNull();
    expect(root.querySelector('img')).toBeNull();
    expect(root.querySelector('[onerror]')).toBeNull();
    expect(root.querySelector('iframe')).toBeNull();

    await editor.destroy();
    root.remove();
  });
});
