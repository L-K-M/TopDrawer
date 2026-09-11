import { $remark } from '@milkdown/kit/utils';
import { visit } from 'unist-util-visit';
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
 * is built, so the text is visible, editable, and preserved. Deferred to a
 * later phase: a node view that renders local/data images and inert HTML
 * previews.
 */

interface MarkdownNode {
  type: string;
  value?: string;
  alt?: string | null;
  url?: string;
  title?: string | null;
}

/** Reconstructs the source form of an image node ("![alt](url \"title\")"). */
function imageSource(node: MarkdownNode): string {
  const title = node.title ? ` "${node.title}"` : '';
  return `![${node.alt ?? ''}](${node.url ?? ''}${title})`;
}

const plainTextFallback = $remark(
  'topdrawer-plain-text-fallback',
  () => () => (tree: unknown) => {
    visit(tree as never, (node: MarkdownNode, index, parent) => {
      if (index === undefined || index === null || !parent) return;
      if (node.type !== 'html' && node.type !== 'image') return;

      const value = node.type === 'html' ? (node.value ?? '') : imageSource(node);
      ((parent as { children: MarkdownNode[] }).children[index] as unknown) = {
        type: 'text',
        value,
      };
    });
  },
);

/**
 * Crepe feature shape (see `@milkdown/crepe/feature/shared`): a function that
 * configures the underlying Milkdown editor.
 */
export const noRawContent = (editor: Editor): void => {
  editor.use(plainTextFallback);
};
