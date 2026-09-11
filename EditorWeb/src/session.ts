import {
  PROTOCOL_VERSION,
  detectTransport,
  parseHostMessage,
  type EditorMessage,
  type HostMessage,
  type Theme,
  type Transport,
} from './bridge';
import { ChangeCoalescer } from './coalescer';
import { RichEditor } from './editor';
import { SourceEditor } from './source';

const PLACEHOLDER = 'Write a note…';

/** Coalescing window for `changed` traffic while typing (ms). */
export const CHANGE_DEBOUNCE_MS = 200;

type Mode = 'rich' | 'source';

/**
 * Owns one note-editing session: the two editor modes, revision discipline,
 * and debounced change reporting.
 *
 * Invariants:
 * - `changed` is emitted only after a local user edit, so a view-only
 *   open/close never normalizes or re-emits the source.
 * - Host messages are handled strictly in order; a second rebuild cannot start
 *   while one is in flight (a late `replaceDocument` used to mount a second
 *   editor into the same container).
 * - `replaceDocument` messages at or below the last applied revision are
 *   dropped: an equal revision with identical text is a host retry, not news.
 * - Only one mode is alive at a time; switching destroys the other editor.
 */
export class EditorSession {
  private transport: Transport;
  private rich: RichEditor | null = null;
  private source: SourceEditor | null = null;
  private mode: Mode = 'rich';
  private theme: Theme = 'light';

  /** Revision last assigned by the host (monotonic). */
  private hostRevision = -1;
  /** Revision of the editor's own change stream; echoed to the host. */
  private editorRevision = 0;
  /** Markdown as loaded by the host — the source of truth while clean. */
  private loadedMarkdown = '';
  private changes: ChangeCoalescer;

  /** Serializes async host-message handling so rebuilds never interleave. */
  private handlerQueue: Promise<void> = Promise.resolve();

  constructor(
    private container: HTMLElement,
    transport?: Transport,
  ) {
    this.transport = transport ?? detectTransport();
    this.changes = new ChangeCoalescer(CHANGE_DEBOUNCE_MS, (markdown) => {
      this.editorRevision += 1;
      this.loadedMarkdown = markdown;
      this.send({ type: 'changed', markdown, editorRevision: this.editorRevision });
    });
  }

  start(): void {
    window.topdrawerEditor = {
      handleMessage: (raw: string) => {
        let parsed: unknown;
        try {
          parsed = JSON.parse(raw);
        } catch {
          this.diagnostic('bad-message', 'host message is not valid JSON');
          return;
        }
        const message = parseHostMessage(parsed);
        if (!message) {
          this.diagnostic('bad-message', 'host message failed validation');
          return;
        }
        window.topdrawerHarness?.log('in', message);
        this.handlerQueue = this.handlerQueue
          .then(() => this.handleHostMessage(message))
          .catch((error) => this.diagnostic('handler-error', String(error)));
      },
    };
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') this.flush();
    });
    // A webview can be torn down without a visibility transition.
    window.addEventListener('pagehide', () => this.flush());
    this.send({ type: 'ready', protocolVersion: PROTOCOL_VERSION });
  }

  private async handleHostMessage(message: HostMessage): Promise<void> {
    switch (message.type) {
      case 'initialize':
        this.theme = message.theme;
        this.applyTheme();
        await this.loadDocument(message.markdown, message.revision);
        break;
      case 'replaceDocument':
        await this.loadDocument(message.markdown, message.revision);
        break;
      case 'focus':
        this.activeEditorFocus();
        break;
      case 'command':
        await this.handleCommand(message.name);
        break;
      case 'setTheme':
        this.theme = message.theme;
        this.applyTheme();
        this.source?.setTheme(this.theme);
        break;
    }
  }

  private async loadDocument(markdown: string, revision: number): Promise<void> {
    if (revision < this.hostRevision) {
      this.diagnostic('stale-replace', `dropped revision ${revision}`);
      return;
    }
    // Same revision and same content is a host retry, not new information:
    // rebuilding would drop focus, undo history, and any edit in flight.
    if (revision === this.hostRevision && markdown === this.loadedMarkdown) {
      return;
    }
    this.hostRevision = revision;
    this.loadedMarkdown = markdown;
    this.changes.reset();
    await this.rebuildEditor();
  }

  private async rebuildEditor(): Promise<void> {
    await this.destroyEditors();
    if (this.mode === 'rich') {
      this.rich = await RichEditor.mount(this.container, {
        markdown: this.loadedMarkdown,
        placeholder: PLACEHOLDER,
        onChange: (md) => this.changes.note(md),
        onOpenLink: (url) => this.openLink(url),
        onFocusChanged: (focused) => this.focusChanged(focused),
      });
      return;
    }
    this.source = new SourceEditor(this.container, {
      markdown: this.loadedMarkdown,
      placeholder: PLACEHOLDER,
      theme: this.theme,
      onChange: (md) => this.changes.note(md),
      onFocusChanged: (focused) => this.focusChanged(focused),
    });
  }

  private async destroyEditors(): Promise<void> {
    if (this.rich) {
      await this.rich.destroy();
      this.rich = null;
    }
    if (this.source) {
      this.source.destroy();
      this.source = null;
    }
  }

  private async handleCommand(name: 'toggleMode' | 'undo' | 'redo'): Promise<void> {
    switch (name) {
      case 'toggleMode':
        await this.toggleMode();
        break;
      // History lives in the active editor (ProseMirror transactions for rich
      // mode, CodeMirror's own stack for source). The browser's native
      // undo stack knows nothing about either.
      case 'undo':
        this.rich?.undo();
        this.source?.undo();
        break;
      case 'redo':
        this.rich?.redo();
        this.source?.redo();
        break;
    }
  }

  private async toggleMode(): Promise<void> {
    // Persist any pending edit before the other mode takes over the container;
    // otherwise it would sit unflushed and be lost if the drawer closed
    // without a further edit.
    this.flush();
    this.loadedMarkdown = this.currentMarkdown();
    this.mode = this.mode === 'rich' ? 'source' : 'rich';
    await this.rebuildEditor();
  }

  private currentMarkdown(): string {
    if (this.changes.pendingMarkdown !== null) return this.changes.pendingMarkdown;
    if (this.rich) return this.rich.getMarkdown();
    if (this.source) return this.source.getMarkdown();
    return this.loadedMarkdown;
  }

  /** Sends any pending local edit immediately (blur, drawer close, terminate). */
  flush(): void {
    this.changes.flush();
  }

  private openLink(url: string): void {
    // Only web links leave the app; every other scheme stays inert.
    if (/^https?:\/\//i.test(url)) {
      this.send({ type: 'openLink', url });
    } else {
      this.diagnostic('blocked-link', url);
    }
  }

  private focusChanged(isFocused: boolean): void {
    if (!isFocused) this.flush();
    this.send({ type: 'focusChanged', isFocused });
  }

  private activeEditorFocus(): void {
    if (this.rich) this.rich.focus();
    else this.source?.focus();
  }

  private applyTheme(): void {
    document.documentElement.dataset.tdTheme = this.theme;
  }

  private diagnostic(code: string, detail?: string): void {
    this.send({ type: 'diagnostic', code, detail });
  }

  private send(message: EditorMessage): void {
    this.transport.send(message);
  }
}
