import {
  PROTOCOL_VERSION,
  detectTransport,
  parseHostMessage,
  type EditorMessage,
  type FormattingBar,
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

/** The host application's appearance, where the platform reports one. */
function preferredTheme(): Theme {
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

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
 *   dropped: the host assigns a fresh revision to every document it sends, so
 *   a repeated revision is a retry, never a new document. Comparing content
 *   instead would clobber a local edit, because `loadedMarkdown` moves on with
 *   every flush while the host's copy stays at the old revision.
 * - Only one mode is alive at a time; switching destroys the other editor.
 */
export class EditorSession {
  private transport: Transport;
  private rich: RichEditor | null = null;
  private source: SourceEditor | null = null;
  private mode: Mode = 'rich';
  /**
   * Until the host's `initialize` arrives, follow the host application's own
   * appearance: the web view inherits it, so this is the same signal the host
   * will send, and it keeps a dark drawer from flashing a light editor. The
   * stylesheet carries the matching canvas fallback for the moment before this
   * runs. `matchMedia` is guarded because the unit tests run in happy-dom.
   */
  private theme: Theme = preferredTheme();
  /** Opt-in chrome: the formatting bar stays out of the way until asked for. */
  private formattingBar: FormattingBar = 'hidden';

  /** Revision last assigned by the host (monotonic). */
  private hostRevision = -1;
  /** Revision of the editor's own change stream; echoed to the host. */
  private editorRevision = 0;
  /**
   * Identity of the document the editor is showing, as the host named it. Echoed
   * on every `changed` so the host can attribute an edit to the note it came from:
   * an edit can arrive after the drawer has already moved to another tab, or after
   * it has closed the drawer and cleared its notion of "the open tab".
   */
  private documentID: string | null = null;
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
      this.send({
        type: 'changed',
        markdown,
        editorRevision: this.editorRevision,
        documentID: this.documentID ?? '',
      });
    });
  }

  start(): void {
    this.applyTheme();
    this.applyFormattingBar();
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
        // A pending edit belongs to the document being replaced, so report it before
        // adopting the new one: the host attributes it by documentID and saves it
        // against the right note. Dropping it here would silently lose the last
        // keystrokes of the note the user just left.
        this.flush();
        this.theme = message.theme;
        this.documentID = message.documentID;
        this.applyTheme();
        // Note on the revision floor: `hostRevision` is a *global* counter in the
        // host, not a per-document one, so a new document's revision is always
        // greater than the previous one's and this guard admits it.
        await this.loadDocument(message.markdown, message.revision);
        break;
      case 'replaceDocument':
        await this.loadDocument(message.markdown, message.revision);
        break;
      case 'focus':
        this.activeEditorFocus();
        break;
      case 'flush':
        // The host asks explicitly because a web view can be hidden or torn down
        // without a visibility change, and a host may be about to terminate.
        this.flush();
        break;
      case 'command':
        await this.handleCommand(message.name);
        break;
      case 'setTheme':
        this.theme = message.theme;
        this.applyTheme();
        this.source?.setTheme(this.theme);
        break;
      case 'setFormattingBar':
        this.formattingBar = message.formattingBar;
        this.applyFormattingBar();
        break;
    }
  }

  private async loadDocument(markdown: string, revision: number): Promise<void> {
    // The host assigns a fresh revision to each document it pushes, so a
    // revision we have already applied is a duplicate or a late arrival. It is
    // dropped on the revision alone: comparing text would let a retry of the
    // pre-edit document rebuild the editor and discard what the user typed
    // (our copy of the text advances with every flush).
    if (revision <= this.hostRevision) {
      if (revision < this.hostRevision) {
        this.diagnostic('stale-replace', `dropped revision ${revision}`);
      }
      return;
    }

    const previousMarkdown = this.loadedMarkdown;
    const previousRevision = this.hostRevision;
    // The host's document wins over anything in flight (it is authoritative for
    // the note), but the user's typing must not vanish without a trace. Which
    // side should win on a real conflict is a Phase 2 decision; for now the
    // host is told.
    if (this.changes.isDirty) {
      this.diagnostic('edit-superseded', 'host document replaced with an edit pending');
    }
    this.loadedMarkdown = markdown;
    this.changes.reset();
    try {
      await this.rebuildEditor();
    } catch (error) {
      // Do not record a revision whose document never made it into an editor:
      // that would drop the host's retry and leave the surface stuck.
      this.loadedMarkdown = previousMarkdown;
      this.hostRevision = previousRevision;
      this.diagnostic('apply-failed', String(error));
      return;
    }
    this.hostRevision = revision;
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

  /**
   * Shown or hidden by stylesheet rather than by adding and removing Crepe's
   * feature: rebuilding the editor to toggle chrome would cost the cursor and
   * the undo history.
   */
  private applyFormattingBar(): void {
    document.documentElement.dataset.tdFormattingBar = this.formattingBar;
  }

  private diagnostic(code: string, detail?: string): void {
    this.send({ type: 'diagnostic', code, detail });
  }

  private send(message: EditorMessage): void {
    this.transport.send(message);
  }
}
