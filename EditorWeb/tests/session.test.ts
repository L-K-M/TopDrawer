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

  it('treats an equal revision with different text as news', async () => {
    const { transport, container, session } = newSession();
    initialize(session, 'x\n', 3);
    await settled(container, 'x');
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'y\n', revision: 3 }));
    await settled(container, 'y');
    expect(transport.ofType('diagnostic')).toEqual([]);
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

  it('keeps a pending edit when the host retries the pre-edit document', async () => {
    const { transport, container, session } = newSession();
    initialize(session, 'original\n', 1);
    await settled(container, 'original');

    // Simulate the host re-sending the same revision/body after a mount.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'original\n', revision: 1 }));
    await new Promise((r) => setTimeout(r, 50));

    // The retry is dropped, so no edit is reported and the editor survives.
    expect(transport.ofType('changed')).toEqual([]);
    expect(container.querySelector('.ProseMirror')).toBeTruthy();
  });
});
