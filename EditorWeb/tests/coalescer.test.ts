import { describe, expect, it, vi } from 'vitest';
import { ChangeCoalescer } from '../src/coalescer';

/**
 * The debounce/flush contract behind "changed fires only after a local edit".
 * Uses injected fake timers so no real time passes.
 */
function makeCoalescer() {
  const emitted: string[] = [];
  const timers = new Map<number, () => void>();
  let nextId = 1;
  const coalescer = new ChangeCoalescer(
    200,
    (markdown) => emitted.push(markdown),
    ((fn: () => void) => {
      const id = nextId++;
      timers.set(id, fn);
      return id;
    }) as unknown as typeof setTimeout,
    ((id: number) => {
      timers.delete(id);
    }) as unknown as typeof clearTimeout,
  );
  return {
    coalescer,
    emitted,
    /** Fires every pending timer, as the event loop would after the delay. */
    advance: () => {
      for (const [id, fn] of [...timers]) {
        timers.delete(id);
        fn();
      }
    },
    pendingTimerCount: () => timers.size,
  };
}

describe('ChangeCoalescer', () => {
  it('emits nothing while clean', () => {
    const { coalescer, emitted, pendingTimerCount } = makeCoalescer();
    expect(coalescer.isDirty).toBe(false);
    coalescer.flush();
    expect(emitted).toEqual([]);
    expect(pendingTimerCount()).toBe(0);
  });

  it('emits once after the debounce window, not per keystroke', () => {
    const { coalescer, emitted, advance, pendingTimerCount } = makeCoalescer();
    coalescer.note('a');
    coalescer.note('ab');
    coalescer.note('abc');
    expect(emitted).toEqual([]);
    expect(pendingTimerCount()).toBe(1);
    advance();
    expect(emitted).toEqual(['abc']);
    expect(coalescer.isDirty).toBe(false);
  });

  it('flush emits immediately and cancels the timer', () => {
    const { coalescer, emitted, advance, pendingTimerCount } = makeCoalescer();
    coalescer.note('typed');
    coalescer.flush();
    expect(emitted).toEqual(['typed']);
    expect(pendingTimerCount()).toBe(0);
    advance();
    expect(emitted).toEqual(['typed']);
  });

  it('flush is idempotent', () => {
    const { coalescer, emitted } = makeCoalescer();
    coalescer.note('once');
    coalescer.flush();
    coalescer.flush();
    expect(emitted).toEqual(['once']);
  });

  it('reset drops a pending change without emitting', () => {
    const { coalescer, emitted, advance } = makeCoalescer();
    coalescer.note('discarded');
    coalescer.reset();
    expect(coalescer.isDirty).toBe(false);
    advance();
    expect(emitted).toEqual([]);
  });

  it('exposes the pending text for mode switches', () => {
    const { coalescer } = makeCoalescer();
    coalescer.note('half-typed');
    expect(coalescer.pendingMarkdown).toBe('half-typed');
    coalescer.flush();
    expect(coalescer.pendingMarkdown).toBeNull();
  });
});

describe('timer wiring', () => {
  it('uses the real timers when none are injected', () => {
    vi.useFakeTimers();
    try {
      const emitted: string[] = [];
      const coalescer = new ChangeCoalescer(200, (markdown) => emitted.push(markdown));
      coalescer.note('real');
      vi.advanceTimersByTime(199);
      expect(emitted).toEqual([]);
      vi.advanceTimersByTime(1);
      expect(emitted).toEqual(['real']);
    } finally {
      vi.useRealTimers();
    }
  });

  /**
   * Browsers throw "Illegal invocation" when a native timer is called with the
   * wrong `this`; happy-dom and Node do not, so this asserts the call shape the
   * browser requires. Without the wrapper this test fails and so does the
   * editor in Chromium (the change only went out on blur).
   */
  it('calls the platform timers as free functions', () => {
    const realSetTimeout = globalThis.setTimeout;
    const realClearTimeout = globalThis.clearTimeout;
    const seen: unknown[] = [];

    globalThis.setTimeout = function (this: unknown, callback: () => void, ms: number) {
      seen.push(this);
      return realSetTimeout(callback, ms);
    } as unknown as typeof setTimeout;
    globalThis.clearTimeout = function (this: unknown, handle: ReturnType<typeof setTimeout>) {
      seen.push(this);
      return realClearTimeout(handle);
    } as unknown as typeof clearTimeout;

    try {
      const emitted: string[] = [];
      const coalescer = new ChangeCoalescer(10, (markdown) => emitted.push(markdown));
      coalescer.note('typed');
      coalescer.flush();

      expect(emitted).toEqual(['typed']);
      expect(seen.length).toBeGreaterThan(0);
      for (const receiver of seen) {
        const freeCall = receiver === undefined || receiver === globalThis || receiver === window;
        expect(freeCall, `timer called with receiver ${String(receiver)}`).toBe(true);
      }
    } finally {
      globalThis.setTimeout = realSetTimeout;
      globalThis.clearTimeout = realClearTimeout;
    }
  });
});
