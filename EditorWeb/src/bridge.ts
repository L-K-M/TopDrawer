/**
 * Versioned host <-> editor bridge protocol.
 *
 * The same wire format works over WKWebView (`window.webkit.messageHandlers`)
 * and WebKitGTK (which exposes the identical `window.webkit.messageHandlers`
 * API to JavaScript). The host pushes messages in by evaluating
 * `window.topdrawerEditor.handleMessage(json)`; the editor pushes out via the
 * `topdrawer` message handler. In the standalone harness there is no native
 * host, so a fallback transport records traffic for inspection.
 *
 * Data-safety rule: `changed` may only carry *local user edits*. Loading or
 * replacing a document must never serialize and re-emit the original string.
 */

export const PROTOCOL_VERSION = 1;

export type Theme = 'light' | 'dark';
export type Platform = 'macos' | 'linux' | 'harness';

/** host -> editor */
export type HostMessage =
  | { type: 'initialize'; markdown: string; theme: Theme; platform: Platform; revision: number }
  | { type: 'replaceDocument'; markdown: string; revision: number }
  | { type: 'focus' }
  | { type: 'command'; name: 'toggleMode' | 'undo' | 'redo' }
  | { type: 'setTheme'; theme: Theme };

/** editor -> host */
export type EditorMessage =
  | { type: 'ready'; protocolVersion: number }
  | { type: 'changed'; markdown: string; editorRevision: number }
  | { type: 'openLink'; url: string }
  | { type: 'focusChanged'; isFocused: boolean }
  | { type: 'diagnostic'; code: string; detail?: string };

export interface Transport {
  send(message: EditorMessage): void;
}

interface WebkitMessageHandlers {
  topdrawer?: { postMessage(message: unknown): void };
}

declare global {
  interface Window {
    webkit?: { messageHandlers?: WebkitMessageHandlers };
    topdrawerEditor?: { handleMessage(raw: string): void };
    topdrawerHarness?: { log(direction: 'in' | 'out', message: unknown): void };
  }
}

/** Real host transport (WKWebView / WebKitGTK). */
export class WebkitTransport implements Transport {
  send(message: EditorMessage): void {
    window.webkit?.messageHandlers?.topdrawer?.postMessage(message);
  }
}

/** Fallback transport for the browser harness: records every message. */
export class HarnessTransport implements Transport {
  constructor(private sink?: (message: EditorMessage) => void) {}
  send(message: EditorMessage): void {
    this.sink?.(message);
    window.topdrawerHarness?.log('out', message);
  }
}

export function detectTransport(sink?: (message: EditorMessage) => void): Transport {
  if (window.webkit?.messageHandlers?.topdrawer) return new WebkitTransport();
  return new HarnessTransport(sink);
}

const THEMES: readonly string[] = ['light', 'dark'];
const PLATFORMS: readonly string[] = ['macos', 'linux', 'harness'];

function isTheme(value: unknown): value is Theme {
  return typeof value === 'string' && THEMES.includes(value);
}

function isPlatform(value: unknown): value is Platform {
  return typeof value === 'string' && PLATFORMS.includes(value);
}

/**
 * Validates an incoming raw host message. Returns null when malformed.
 *
 * Deliberately strict: an unknown theme, platform or revision is a host bug,
 * and silently coercing it (wrong theme, missing platform bindings, NaN
 * revision comparisons) hides the bug instead of surfacing it.
 */
export function parseHostMessage(raw: unknown): HostMessage | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const msg = raw as Record<string, unknown>;
  switch (msg.type) {
    case 'initialize':
      if (typeof msg.markdown !== 'string') return null;
      if (!Number.isInteger(msg.revision) || !isTheme(msg.theme) || !isPlatform(msg.platform)) {
        return null;
      }
      return {
        type: 'initialize',
        markdown: msg.markdown,
        theme: msg.theme,
        platform: msg.platform,
        revision: msg.revision as number,
      };
    case 'replaceDocument':
      if (typeof msg.markdown !== 'string' || !Number.isInteger(msg.revision)) return null;
      return { type: 'replaceDocument', markdown: msg.markdown, revision: msg.revision as number };
    case 'focus':
      return { type: 'focus' };
    case 'command':
      if (msg.name === 'toggleMode' || msg.name === 'undo' || msg.name === 'redo') {
        return { type: 'command', name: msg.name };
      }
      return null;
    case 'setTheme':
      if (!isTheme(msg.theme)) return null;
      return { type: 'setTheme', theme: msg.theme };
    default:
      return null;
  }
}
