import { CrepeBuilder } from '@milkdown/crepe/builder';
import { toolbar } from '@milkdown/crepe/feature/toolbar';
import { topBar } from '@milkdown/crepe/feature/top-bar';
import { codeMirror } from '@milkdown/crepe/feature/code-mirror';
import { cursor } from '@milkdown/crepe/feature/cursor';
import { linkTooltip } from '@milkdown/crepe/feature/link-tooltip';
import { listItem } from '@milkdown/crepe/feature/list-item';
import { placeholder } from '@milkdown/crepe/feature/placeholder';
import { table } from '@milkdown/crepe/feature/table';
import { editorViewCtx } from '@milkdown/kit/core';
import { undo, redo } from 'prosemirror-history';
import type { Command } from 'prosemirror-state';

// Only the CSS for enabled features; the monolithic style.css would drag in
// KaTeX fonts, the AI panel, image upload and slash-menu chrome.
import '@milkdown/crepe/theme/common/prosemirror.css';
import '@milkdown/crepe/theme/common/reset.css';
import '@milkdown/crepe/theme/common/code-mirror.css';
import '@milkdown/crepe/theme/common/cursor.css';
import '@milkdown/crepe/theme/common/link-tooltip.css';
import '@milkdown/crepe/theme/common/list-item.css';
import '@milkdown/crepe/theme/common/placeholder.css';
import '@milkdown/crepe/theme/common/toolbar.css';
import '@milkdown/crepe/theme/common/table.css';
import '@milkdown/crepe/theme/common/top-bar.css';

export interface RichEditorOptions {
  markdown: string;
  placeholder: string;
  /** Fires only on local user edits, never on load. Receives serialized Markdown. */
  onChange(markdown: string): void;
  /** Links must open through the host's external-browser path, never in-view. */
  onOpenLink(url: string): void;
  onFocusChanged?(isFocused: boolean): void;
}

/**
 * Rich WYSIWYG mode: a deliberately slim Milkdown/Crepe assembly built with
 * CrepeBuilder so unused features (image upload, LaTeX, AI, slash menu / block
 * handle) are tree-shaken out of the bundle entirely. Markdown in, Markdown
 * out. Serialization only ever happens in response to a local change reported
 * by the listener, so a view-only open/close cycle cannot normalize the source.
 *
 * Raw HTML in a note stays inert: the CommonMark preset parses HTML blocks as
 * text (no HTML nodes are created) and is deliberately NOT sanitized on the way
 * in, because rewriting the source on load would damage the user's bytes. The
 * shipped page additionally runs under a strict CSP; see the harness README.
 */
export class RichEditor {
  private state = { destroyed: false };

  /**
   * Set by the first real user interaction inside the editor.
   *
   * Crepe applies its parsed `defaultValue` in a transaction *after* create()
   * resolves, so `markdownUpdated` fires shortly after mount with remark's
   * normalized serialization ('-' bullets become '*', '---' becomes '***').
   * Reporting that would rewrite an untouched note purely because it was
   * opened. Plugin-driven normalization never accompanies these DOM events,
   * and they all precede the transaction they cause, so a user's first edit is
   * never dropped.
   */
  private userInteracted = false;

  private constructor(
    private root: HTMLElement,
    private builder: CrepeBuilder,
  ) {}

  static async mount(root: HTMLElement, options: RichEditorOptions): Promise<RichEditor> {
    const builder = new CrepeBuilder({ root, defaultValue: options.markdown });
    const editor = new RichEditor(root, builder);
    builder
      .addFeature(toolbar)
      .addFeature(topBar)
      .addFeature(codeMirror)
      .addFeature(cursor)
      .addFeature(linkTooltip, { onCopyLink: (link: string) => options.onOpenLink(link) })
      .addFeature(listItem)
      .addFeature(placeholder, { text: options.placeholder, mode: 'doc' })
      .addFeature(table);

    builder.on((api) => {
      api.markdownUpdated((_ctx, markdown, prevMarkdown) => {
        if (editor.state.destroyed || !editor.userInteracted) return;
        if (markdown === prevMarkdown) return;
        options.onChange(markdown);
      });
    });

    await builder.create();
    editor.wireUserInteraction();
    editor.wireLinks(options.onOpenLink);
    editor.wireFocus(options.onFocusChanged);
    return editor;
  }

  /**
   * Records genuine user intent: typing, IME composition, paste/drop, or a
   * toolbar button (which mutates the document without any key event).
   */
  private wireUserInteraction(): void {
    const mark = () => {
      this.userInteracted = true;
    };
    for (const event of ['keydown', 'beforeinput', 'paste', 'drop', 'cut', 'click']) {
      this.root.addEventListener(event, mark, { capture: true });
    }
  }

  /**
   * Anchors inside the document must never navigate the web view (that would
   * destroy the session). Intercept the default and hand the URL to the host.
   */
  private wireLinks(onOpenLink: (url: string) => void): void {
    this.root.addEventListener('click', (event) => {
      const anchor = (event.target as Element | null)?.closest('a[href]');
      if (!(anchor instanceof HTMLAnchorElement)) return;
      event.preventDefault();
      onOpenLink(anchor.href);
    });
  }

  /**
   * Report focus transitions. `focusout` also fires when focus moves between
   * elements inside the editor (toolbar, tooltip), so only a `relatedTarget`
   * outside the subtree counts as leaving; the session flushes on blur.
   */
  private wireFocus(onFocusChanged?: (isFocused: boolean) => void): void {
    if (!onFocusChanged) return;
    let focused = false;

    this.root.addEventListener('focusin', () => {
      if (focused) return;
      focused = true;
      onFocusChanged(true);
    });
    this.root.addEventListener('focusout', (event) => {
      if (!focused) return;
      const next = event.relatedTarget as Node | null;
      if (next && this.root.contains(next)) return;
      focused = false;
      onFocusChanged(false);
    });
  }

  getMarkdown(): string {
    return this.builder.getMarkdown();
  }

  undo(): void {
    this.run(undo);
  }

  redo(): void {
    this.run(redo);
  }

  /** Dispatches a ProseMirror command against the live editor view. */
  private run(command: Command): void {
    if (this.state.destroyed) return;
    this.builder.editor.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      command(view.state, view.dispatch, view);
    });
  }

  focus(): void {
    this.root.querySelector<HTMLElement>('.ProseMirror')?.focus();
  }

  async destroy(): Promise<void> {
    this.state.destroyed = true;
    await this.builder.destroy();
    this.root.replaceChildren();
  }
}
