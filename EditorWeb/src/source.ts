import { EditorView, keymap, placeholder as cmPlaceholder } from '@codemirror/view';
import { Compartment } from '@codemirror/state';
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
  undo,
  redo,
} from '@codemirror/commands';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { defaultHighlightStyle, syntaxHighlighting, HighlightStyle } from '@codemirror/language';
import { searchKeymap, highlightSelectionMatches } from '@codemirror/search';
import { tags } from '@lezer/highlight';
import type { Theme } from './bridge';

export interface SourceEditorOptions {
  markdown: string;
  placeholder: string;
  theme: Theme;
  onChange(markdown: string): void;
  onFocusChanged?(isFocused: boolean): void;
}

/**
 * Source mode: raw Markdown in CodeMirror 6. The document stays plain text, so
 * this mode is byte-exact by construction and doubles as the recovery path for
 * documents rich mode cannot represent safely.
 *
 * Theme-dependent extensions live in compartments so a host theme switch
 * reconfigures in place instead of destroying undo history and the cursor.
 */
export class SourceEditor {
  private view: EditorView;
  private themeCompartment = new Compartment();
  private highlightCompartment = new Compartment();

  constructor(root: HTMLElement, options: SourceEditorOptions) {
    const dark = options.theme === 'dark';
    this.view = new EditorView({
      parent: root,
      doc: options.markdown,
      extensions: [
        history(),
        markdown({ base: markdownLanguage, addKeymap: true }),
        EditorView.lineWrapping,
        cmPlaceholder(options.placeholder),
        highlightSelectionMatches(),
        keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab]),
        this.highlightCompartment.of(SourceEditor.highlighting(dark)),
        baseTheme,
        this.themeCompartment.of(dark ? [darkEditorTheme] : []),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) options.onChange(this.view.state.doc.toString());
        }),
        EditorView.domEventHandlers({
          focus: () => options.onFocusChanged?.(true),
          blur: () => options.onFocusChanged?.(false),
        }),
      ],
    });
  }

  getMarkdown(): string {
    return this.view.state.doc.toString();
  }

  undo(): void {
    undo(this.view);
  }

  redo(): void {
    redo(this.view);
  }

  /** Reconfigures colors in place; document, selection and history survive. */
  setTheme(theme: Theme): void {
    const dark = theme === 'dark';
    this.view.dispatch({
      effects: [
        this.themeCompartment.reconfigure(dark ? [darkEditorTheme] : []),
        this.highlightCompartment.reconfigure(SourceEditor.highlighting(dark)),
      ],
    });
  }

  focus(): void {
    this.view.focus();
  }

  destroy(): void {
    this.view.destroy();
  }

  private static highlighting(dark: boolean) {
    return syntaxHighlighting(dark ? darkHighlight : defaultHighlightStyle);
  }
}

const baseTheme = EditorView.theme({
  '&': {
    backgroundColor: 'transparent',
    fontSize: '13px',
    height: '100%',
  },
  '.cm-content': {
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
    padding: '10px',
    caretColor: 'var(--crepe-color-primary, #b45309)',
  },
  '.cm-scroller': { fontFamily: 'inherit', overflow: 'auto' },
  '&.cm-focused': { outline: 'none' },
});

const darkEditorTheme = EditorView.theme(
  {
    '&': { color: '#eae1d9' },
    '.cm-gutters': { backgroundColor: 'transparent', border: 'none' },
  },
  { dark: true },
);

const darkHighlight = HighlightStyle.define([
  { tag: tags.heading, fontWeight: '700', color: '#f4bd6f' },
  { tag: tags.emphasis, fontStyle: 'italic' },
  { tag: tags.strong, fontWeight: '700' },
  { tag: tags.link, color: '#7cb3f7' },
  { tag: tags.url, color: '#7cb3f7' },
  { tag: tags.monospace, color: '#ffb4ab' },
  { tag: tags.quote, color: '#a8c7a0' },
  { tag: tags.processingInstruction, color: '#c9b8a8' },
]);
