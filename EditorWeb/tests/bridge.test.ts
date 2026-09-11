import { describe, expect, it } from 'vitest';
import { parseHostMessage, PROTOCOL_VERSION } from '../src/bridge';

describe('parseHostMessage', () => {
  it('accepts a well-formed initialize', () => {
    expect(
      parseHostMessage({
        type: 'initialize',
        markdown: '# Hi',
        theme: 'dark',
        platform: 'macos',
        revision: 3,
      }),
    ).toEqual({ type: 'initialize', markdown: '# Hi', theme: 'dark', platform: 'macos', revision: 3 });
  });

  it('rejects non-objects and missing fields', () => {
    expect(parseHostMessage(null)).toBeNull();
    expect(parseHostMessage('initialize')).toBeNull();
    expect(parseHostMessage({ type: 'initialize', markdown: 1, revision: 1 })).toBeNull();
    expect(parseHostMessage({ type: 'replaceDocument', markdown: 'x' })).toBeNull();
  });

  it('rejects invalid theme/platform instead of coercing them', () => {
    expect(
      parseHostMessage({
        type: 'initialize',
        markdown: '',
        theme: 'Dark',
        platform: 'macos',
        revision: 0,
      }),
    ).toBeNull();
    expect(
      parseHostMessage({
        type: 'initialize',
        markdown: '',
        theme: 'light',
        platform: 'macOS',
        revision: 0,
      }),
    ).toBeNull();
    expect(parseHostMessage({ type: 'setTheme', theme: 'purple' })).toBeNull();
  });

  it('requires an integer revision', () => {
    const base = { type: 'replaceDocument', markdown: 'x' };
    expect(parseHostMessage({ ...base, revision: NaN })).toBeNull();
    expect(parseHostMessage({ ...base, revision: 1.5 })).toBeNull();
    expect(parseHostMessage({ ...base, revision: '1' })).toBeNull();
    expect(parseHostMessage({ ...base, revision: 1 })).toEqual({
      type: 'replaceDocument',
      markdown: 'x',
      revision: 1,
    });
  });

  it('rejects unknown commands', () => {
    expect(parseHostMessage({ type: 'command', name: 'rm -rf' })).toBeNull();
    expect(parseHostMessage({ type: 'command', name: 'toggleMode' })).toEqual({
      type: 'command',
      name: 'toggleMode',
    });
  });

  it('protocol version is pinned at 1', () => {
    expect(PROTOCOL_VERSION).toBe(1);
  });
});
