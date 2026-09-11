import { $remark } from '@milkdown/kit/utils';
import type { Editor } from '@milkdown/kit/core';

/**
 * Keeps raw HTML and images out of the rich document.
 *
 * The improvement plan requires rich mode to neither render raw HTML nor fetch
 * remote images in v1, and Milkdown's HTML parser builds real DOM elements from
 * raw HTML: `<img src=x onerror=...>` became a live `<img>` (its load blocked
 * only by the page CSP) and `![alt](url)` an `<img>` that attempted a request.
 *
 * Rather than sanitizing (which would rewrite the user's bytes on load), this
 * replaces those nodes with their literal Markdown *before* the document model
 * is built, so the text stays visible, editable, and preserved. Deferred to a
 * later phase: a node view that renders local/data images and inert HTML
 * previews, which would also keep the source byte-exact.
 */

interface MarkdownNode {
  type: string;
  value?: string;
  alt?: string | null;
  url?: string;
  title?: string | null;
  children?: MarkdownNode[];
}

/** Node kinds rich mode must not turn into DOM. */
const UNRENDERED_NODES = new Set(['html', 'image']);

/** Reconstructs an image node's source form: `![alt](url "title")`. */
function imageSource(node: MarkdownNode): string {
  const title = node.title ? ` "${node.title}"` : '';
  return `![${node.alt ?? ''}](${node.url ?? ''}${title})`;
}

/** Depth-first replacement of unrendered nodes with literal text nodes. */
function toPlainText(node: MarkdownNode): void {
  const children = node.children;
  if (!children) return;

  for (let index = 0; index < children.length; index += 1) {
    const child = children[index];
    if (UNRENDERED_NODES.has(child.type)) {
      children[index] = {
        type: 'text',
        value: child.type === 'html' ? (child.value ?? '') : imageSource(child),
      };
      continue;
    }
    toPlainText(child);
  }
}

const plainTextFallback = $remark('topdrawer-plain-text-fallback', () => () => (tree: unknown) => {
  toPlainText(tree as MarkdownNode);
});

/**
 * Crepe feature shape (see `@milkdown/crepe/feature/shared`): a function that
 * configures the underlying Milkdown editor.
 */
export const noRawContent = (editor: Editor): void => {
  editor.use(plainTextFallback);
};
