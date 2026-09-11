// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest';
import { EditorSession } from '../src/session';
import type { EditorMessage, Transport } from '../src/bridge';

/** In-memory transport capturing every editor -> host message. */
class FakeTransport implements Transport {
  messages: EditorMessage[] = [];
  send(message: EditorMessage): void {
    this.messages.push(message);
  }
  ofType<T extends EditorMessage['type']>(type: T) {
    return this.messages.filter((m) => m.type === type);
  }
}

function handleMessage(json: string) {
  window.topdrawerEditor?.handleMessage(json);
}

function initialize(session: EditorSession, markdown: string, revision: number) {
  handleMessage(JSON.stringify({ type: 'initialize', markdown, theme: 'light', platform: 'harness', revision }));
}

/** Polls instead of sleeping: a mount is asynchronous and a fixed delay races it. */
async function waitFor(condition: () => boolean, timeoutMs = 2000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error('waitFor timed out');
    await new Promise((r) => setTimeout(r, 5));
  }
}

async function settled(container: HTMLElement, expectedText: string): Promise<void> {
  await waitFor(
    () =>
      container.querySelector('.ProseMirror') !== null &&
      (container.textContent ?? '').includes(expectedText),
  );
}

function newSession() {
  const transport = new FakeTransport();
  const container = document.createElement('div');
  document.body.appendChild(container);
  const session = new EditorSession(container, transport);
  session.start();
  return { transport, container, session };
}

describe('EditorSession', () => {
  it('announces readiness with the protocol version', () => {
    const { transport } = newSession();
    expect(transport.ofType('ready')).toEqual([{ type: 'ready', protocolVersion: 1 }]);
  });

  it('load + flush without edits sends no changed message', async () => {
    const { transport, container, session } = newSession();
    initialize(session, '# Note\n', 1);
    await settled(container, 'Note');
    session.flush();
    expect(transport.ofType('changed')).toEqual([]);
  });

  it('drops a stale replaceDocument and reports a diagnostic', async () => {
    const { transport, container, session } = newSession();
    initialize(session, 'new\n', 5);
    await settled(container, 'new');
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'OLD\n', revision: 2 }));
    await new Promise((r) => setTimeout(r, 50));

    expect(transport.ofType('diagnostic')).toContainEqual({
      type: 'diagnostic',
      code: 'stale-replace',
      detail: 'dropped revision 2',
    });
    expect(transport.ofType('changed')).toEqual([]);
    expect(container.textContent).toContain('new');
  });

  it('accepts a newer replaceDocument and renders the new text', async () => {
    const { transport, container, session } = newSession();
    initialize(session, 'v1\n', 1);
    await settled(container, 'v1');
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'v2\n', revision: 2 }));
    await settled(container, 'v2');
    session.flush();
    expect(transport.ofType('changed')).toEqual([]);
  });

  it('ignores an identical host retry without rebuilding', async () => {
    const { container, session } = newSession();
    initialize(session, 'same\n', 1);
    await settled(container, 'same');
    const editorBefore = container.querySelector('.ProseMirror');

    // Same revision, same text: a redelivery must not churn the editor.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'same\n', revision: 1 }));
    await new Promise((r) => setTimeout(r, 50));

    expect(container.querySelector('.ProseMirror')).toBe(editorBefore);
  });

  it('serializes concurrent host messages so only one editor is mounted', async () => {
    const { container, session } = newSession();
    initialize(session, 'one\n', 1);
    // Deliver a rebuild-triggering message in the same tick, while the first
    // mount is still in flight.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'two\n', revision: 2 }));
    await settled(container, 'two');

    expect(container.querySelectorAll('.ProseMirror')).toHaveLength(1);
  });

  it('ignores a repeated revision even when its text differs', async () => {
    const { transport, container, session } = newSession();
    initialize(session, 'x\n', 3);
    await settled(container, 'x');
    const editorBefore = container.querySelector('.ProseMirror');

    // The host bumps the revision for every document it sends, so a repeated
    // revision carries no new information. Content comparison would rebuild
    // the editor and discard a local edit whose text has moved on.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'y\n', revision: 3 }));
    await new Promise((r) => setTimeout(r, 50));

    expect(container.querySelector('.ProseMirror')).toBe(editorBefore);
    expect(container.textContent).toContain('x');
    expect(transport.ofType('diagnostic')).toEqual([]);

    // A later revision is still honoured: the guard drops duplicates, not
    // everything after one.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'z\n', revision: 4 }));
    await settled(container, 'z');
  });

  it('answers a flush request without inventing a change', async () => {
    const { transport, container, session } = newSession();
    initialize(session, '# Note\n', 1);
    await settled(container, 'Note');

    handleMessage(JSON.stringify({ type: 'flush' }));
    await new Promise((r) => setTimeout(r, 30));

    expect(transport.ofType('changed')).toEqual([]);
  });

  it('rejects malformed host JSON with a diagnostic instead of throwing', async () => {
    const { transport, session } = newSession();
    handleMessage('not json');
    handleMessage(JSON.stringify({ type: 'nonsense' }));
    await waitFor(() => transport.ofType('diagnostic').length >= 2);
    expect(transport.ofType('diagnostic').map((d) => (d as { code: string }).code)).toEqual([
      'bad-message',
      'bad-message',
    ]);
  });

  it('ignores an identical host retry and keeps the mounted editor', async () => {
    const { transport, container, session } = newSession();
    initialize(session, 'original\n', 1);
    await settled(container, 'original');
    const editorBefore = container.querySelector('.ProseMirror');

    // Same revision and text: a redelivery must not rebuild.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'original\n', revision: 1 }));
    await new Promise((r) => setTimeout(r, 50));

    expect(container.querySelector('.ProseMirror')).toBe(editorBefore);
    expect(transport.ofType('changed')).toEqual([]);
  });

  // The dirty-retry case (a retry arriving while an edit is pending) cannot be
  // reproduced here: happy-dom has no input pipeline, so no local edit can be
  // simulated. It is covered end to end by tests/smoke.mjs, which types into a
  // real engine. The guard itself no longer depends on dirtiness: an identical
  // revision and body is dropped regardless of pending state.
});
