// @vitest-environment happy-dom
import { describe, expect, it, vi } from 'vitest';
import { RichEditor } from '../src/editor';

/**
 * The editor root is the session's container, which outlives a mode switch or a
 * host replaceDocument. If listeners outlive destroy() they stack up, and one
 * click then produces several openLink/focusChanged messages.
 */
describe('editor listener lifetime', () => {
  it('does not stack listeners across mounts in the same container', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);
    const onOpenLink = vi.fn();

    const options = {
      markdown: 'A [link](https://example.com/page).\n',
      placeholder: '',
      onChange: () => {},
      onOpenLink,
    };

    for (let mount = 0; mount < 3; mount += 1) {
      const editor = await RichEditor.mount(root, options);
      if (mount < 2) await editor.destroy();
      else {
        // Only the last (live) mount may react to the click.
        const anchor = root.querySelector('a[href]');
        expect(anchor, 'the link must be rendered').toBeTruthy();
        anchor!.dispatchEvent(
          new MouseEvent('click', { bubbles: true, cancelable: true, ctrlKey: true }),
        );
        expect(onOpenLink).toHaveBeenCalledTimes(1);
        await editor.destroy();
      }
    }

    root.remove();
  });

  it('reports focus changes without duplicates', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);
    const onFocusChanged = vi.fn();
    const options = {
      markdown: 'note\n',
      placeholder: '',
      onChange: () => {},
      onOpenLink: () => {},
      onFocusChanged,
    };

    const first = await RichEditor.mount(root, options);
    await first.destroy();
    const second = await RichEditor.mount(root, options);

    root.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
    expect(onFocusChanged).toHaveBeenCalledTimes(1);
    expect(onFocusChanged).toHaveBeenCalledWith(true);

    await second.destroy();
    root.remove();
  });
});
