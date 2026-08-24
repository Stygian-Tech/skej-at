import type { PostPlan, RichFacet } from "@/lib/skejTypes";

export type SocialMarkdownCommand =
  | "bold"
  | "italic"
  | "strike"
  | "code"
  | "link"
  | "quote"
  | "unordered-list"
  | "ordered-list";

export interface SocialMarkdownProjection {
  text: string;
  facets: RichFacet[];
}

export interface MarkdownCommandResult {
  text: string;
  selectionStart: number;
  selectionEnd: number;
}

export interface ProjectionSegment {
  text: string;
  uri?: string;
}

interface CompilationBuffer extends SocialMarkdownProjection {
  suppressedFacetRanges: Array<{ byteStart: number; byteEnd: number }>;
}

const ESCAPABLE_MARKDOWN = /[\\`*{}\[\]()#+\-.!_>~]/u;
const HTTP_URL_AT_START = /^https?:\/\/[^\s<>"']+/iu;
const SIMPLE_TRAILING_PUNCTUATION = /[.,!?;:]+$/u;
const TAG_SEPARATOR = /[\s\u00AD\u2060\u200A\u200B\u200C\u200D\u20E2]/u;

function byteLength(text: string): number {
  return new TextEncoder().encode(text).length;
}

function linkFacet(byteStart: number, byteEnd: number, uri: string): RichFacet {
  return {
    index: { byteStart, byteEnd },
    features: [{ $type: "app.bsky.richtext.facet#link", uri }],
  };
}

function tagFacet(byteStart: number, byteEnd: number, tag: string): RichFacet {
  return {
    index: { byteStart, byteEnd },
    features: [{ $type: "app.bsky.richtext.facet#tag", tag }],
  };
}

function validHTTPURL(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function trimBareURL(value: string): string {
  let candidate = value.replace(SIMPLE_TRAILING_PUNCTUATION, "");
  const pairs: Array<[string, string]> = [
    ["(", ")"],
    ["[", "]"],
    ["{", "}"],
  ];
  let changed = true;
  while (changed) {
    changed = false;
    for (const [open, close] of pairs) {
      if (
        candidate.endsWith(close) &&
        candidate.split(close).length > candidate.split(open).length
      ) {
        candidate = candidate.slice(0, -1);
        changed = true;
      }
    }
  }
  return candidate;
}

function findClosing(source: string, marker: string, start: number): number {
  let index = start;
  while (index < source.length) {
    const found = source.indexOf(marker, index);
    if (found < 0) return -1;
    let slashCount = 0;
    for (let cursor = found - 1; cursor >= 0 && source[cursor] === "\\"; cursor -= 1) {
      slashCount += 1;
    }
    const previous = source[found - 1] ?? "";
    const next = source[found + marker.length] ?? "";
    const intrawordUnderscore =
      marker.includes("_") && /[\p{L}\p{N}]/u.test(previous) && /[\p{L}\p{N}]/u.test(next);
    if (slashCount % 2 === 0 && !intrawordUnderscore) return found;
    index = found + marker.length;
  }
  return -1;
}

function findLinkClose(source: string, start: number): { labelEnd: number; urlEnd: number } | null {
  const labelEnd = findClosing(source, "]", start);
  if (labelEnd < 0 || source[labelEnd + 1] !== "(") return null;
  let depth = 1;
  let cursor = labelEnd + 2;
  while (cursor < source.length) {
    if (source[cursor] === "\\") {
      cursor += 2;
      continue;
    }
    if (source[cursor] === "(") depth += 1;
    if (source[cursor] === ")") {
      depth -= 1;
      if (depth === 0) return { labelEnd, urlEnd: cursor };
    }
    cursor += 1;
  }
  return null;
}

function appendProjection(
  target: CompilationBuffer,
  addition: CompilationBuffer
): void {
  const byteOffset = byteLength(target.text);
  target.text += addition.text;
  target.facets.push(
    ...addition.facets.map((facet) => ({
      ...facet,
      index: {
        byteStart: facet.index.byteStart + byteOffset,
        byteEnd: facet.index.byteEnd + byteOffset,
      },
    }))
  );
  target.suppressedFacetRanges.push(
    ...addition.suppressedFacetRanges.map((range) => ({
      byteStart: range.byteStart + byteOffset,
      byteEnd: range.byteEnd + byteOffset,
    }))
  );
}

function compileInline(source: string): CompilationBuffer {
  const projection: CompilationBuffer = {
    text: "",
    facets: [],
    suppressedFacetRanges: [],
  };
  let index = 0;

  const append = (text: string) => {
    projection.text += text;
  };

  while (index < source.length) {
    if (source[index] === "\\" && source[index + 1]?.match(ESCAPABLE_MARKDOWN)) {
      const byteStart = byteLength(projection.text);
      append(source[index + 1]);
      projection.suppressedFacetRanges.push({
        byteStart,
        byteEnd: byteLength(projection.text),
      });
      index += 2;
      continue;
    }

    if (source[index] === "<") {
      const htmlEnd = source.indexOf(">", index + 1);
      if (htmlEnd >= 0) {
        const byteStart = byteLength(projection.text);
        append(source.slice(index, htmlEnd + 1));
        projection.suppressedFacetRanges.push({
          byteStart,
          byteEnd: byteLength(projection.text),
        });
        index = htmlEnd + 1;
        continue;
      }
    }

    if (source.startsWith("![", index)) {
      const imageClose = findLinkClose(source, index + 2);
      if (imageClose) {
        const byteStart = byteLength(projection.text);
        append(source.slice(index, imageClose.urlEnd + 1));
        projection.suppressedFacetRanges.push({
          byteStart,
          byteEnd: byteLength(projection.text),
        });
        index = imageClose.urlEnd + 1;
        continue;
      }
    }

    if (source[index] === "[") {
      const close = findLinkClose(source, index + 1);
      if (close) {
        const labelSource = source.slice(index + 1, close.labelEnd);
        const uri = source.slice(close.labelEnd + 2, close.urlEnd).trim();
        if (labelSource && validHTTPURL(uri)) {
          const label = compileInline(labelSource);
          const byteStart = byteLength(projection.text);
          appendProjection(projection, label);
          const byteEnd = byteLength(projection.text);
          projection.facets = projection.facets.filter(
            (facet) => facet.index.byteEnd <= byteStart || facet.index.byteStart >= byteEnd
          );
          projection.facets.push(linkFacet(byteStart, byteEnd, uri));
          index = close.urlEnd + 1;
          continue;
        }
        const byteStart = byteLength(projection.text);
        append(source.slice(index, close.urlEnd + 1));
        projection.suppressedFacetRanges.push({
          byteStart,
          byteEnd: byteLength(projection.text),
        });
        index = close.urlEnd + 1;
        continue;
      }
    }

    const urlMatch = source.slice(index).match(HTTP_URL_AT_START)?.[0];
    if (urlMatch) {
      const uri = trimBareURL(urlMatch);
      if (validHTTPURL(uri)) {
        const byteStart = byteLength(projection.text);
        append(uri);
        projection.facets.push(linkFacet(byteStart, byteStart + byteLength(uri), uri));
        index += uri.length;
        continue;
      }
    }

    const previous = source[index - 1] ?? "";
    const next = source[index + (source.startsWith("__", index) ? 2 : 1)] ?? "";
    const intrawordUnderscore =
      source[index] === "_" && /[\p{L}\p{N}]/u.test(previous) && /[\p{L}\p{N}]/u.test(next);
    const marker = source.startsWith("**", index)
      ? "**"
      : source.startsWith("__", index) && !intrawordUnderscore
        ? "__"
      : source.startsWith("~~", index)
        ? "~~"
        : source[index] === "*"
          ? "*"
          : source[index] === "_" && !intrawordUnderscore
            ? "_"
          : source[index] === "`"
            ? "`"
            : null;
    if (marker) {
      const closing = findClosing(source, marker, index + marker.length);
      if (closing > index + marker.length) {
        const content = source.slice(index + marker.length, closing);
        if (marker === "`") {
          const byteStart = byteLength(projection.text);
          append(content);
          projection.suppressedFacetRanges.push({
            byteStart,
            byteEnd: byteLength(projection.text),
          });
        } else appendProjection(projection, compileInline(content));
        index = closing + marker.length;
        continue;
      }
    }

    append(source[index]);
    index += 1;
  }

  return projection;
}

function addTagFacets(projection: CompilationBuffer): void {
  let index = 0;
  while (index < projection.text.length) {
    const marker = projection.text[index];
    const boundary = index === 0 || /\s/u.test(projection.text[index - 1]);
    if ((marker !== "#" && marker !== "＃") || !boundary || projection.text[index + 1] === "\uFE0F") {
      index += 1;
      continue;
    }
    let end = index + 1;
    while (end < projection.text.length && !TAG_SEPARATOR.test(projection.text[end])) end += 1;
    let body = projection.text.slice(index + 1, end);
    while (body && /\p{P}/u.test(body.at(-1) ?? "")) body = body.slice(0, -1);
    const hasSubstance = Array.from(body).some(
      (character) => !/[\p{N}\p{P}\s]/u.test(character)
    );
    const displayEnd = index + 1 + body.length;
    const byteStart = byteLength(projection.text.slice(0, index));
    const byteEnd = byteLength(projection.text.slice(0, displayEnd));
    const overlaps = projection.facets.some(
      (facet) => facet.index.byteStart < byteEnd && facet.index.byteEnd > byteStart
    );
    const suppressed = projection.suppressedFacetRanges.some(
      (range) => range.byteStart < byteEnd && range.byteEnd > byteStart
    );
    if (body && body.length <= 64 && hasSubstance && !overlaps && !suppressed) {
      projection.facets.push(tagFacet(byteStart, byteEnd, body));
    }
    index = Math.max(end, index + 1);
  }
}

/**
 * Compiles Skej's deliberately small social-Markdown subset to the exact plain
 * text and rich-text facets Bluesky will receive. Unsupported Markdown remains
 * literal so the preview never promises formatting the network cannot render.
 */
export function compileSocialMarkdown(source: string): SocialMarkdownProjection {
  const normalized = source.replace(/\r\n?/gu, "\n");
  const lines = normalized.split("\n");
  const projection: CompilationBuffer = {
    text: "",
    facets: [],
    suppressedFacetRanges: [],
  };
  let fenceDelimiter: "```" | "~~~" | null = null;

  lines.forEach((line, lineIndex) => {
    if (lineIndex > 0) projection.text += "\n";
    const trimmed = line.trim();
    const delimiter = trimmed.startsWith("```")
      ? "```"
      : trimmed.startsWith("~~~")
        ? "~~~"
        : null;
    if (fenceDelimiter) {
      const byteStart = byteLength(projection.text);
      projection.text += line;
      projection.suppressedFacetRanges.push({
        byteStart,
        byteEnd: byteLength(projection.text),
      });
      if (delimiter === fenceDelimiter) fenceDelimiter = null;
      return;
    }
    if (delimiter) {
      fenceDelimiter = delimiter;
      const byteStart = byteLength(projection.text);
      projection.text += line;
      projection.suppressedFacetRanges.push({
        byteStart,
        byteEnd: byteLength(projection.text),
      });
      return;
    }
    if (
      /^#{1,6}\s/u.test(trimmed) ||
      /^(---|\*\*\*|___)$/u.test(trimmed) ||
      /^[-+*]\s+\[[ xX]\]\s/u.test(trimmed) ||
      trimmed.startsWith("|")
    ) {
      const byteStart = byteLength(projection.text);
      projection.text += line;
      projection.suppressedFacetRanges.push({
        byteStart,
        byteEnd: byteLength(projection.text),
      });
      return;
    }

    const indentation = line.match(/^\s*/u)?.[0] ?? "";
    let content = line.slice(indentation.length);
    let prefix = indentation;
    while (content.startsWith(">")) {
      content = content.slice(1);
      if (content.startsWith(" ")) content = content.slice(1);
      prefix += "› ";
    }
    const unordered = content.match(/^[-+*]\s+(.*)$/u);
    const ordered = content.match(/^(\d+)[.)]\s+(.*)$/u);
    if (unordered && !/^\[[ xX]\]\s/u.test(unordered[1])) {
      prefix += "• ";
      content = unordered[1];
    } else if (ordered) {
      prefix += `${ordered[1]}. `;
      content = ordered[2];
    }
    projection.text += prefix;
    appendProjection(projection, compileInline(content));
  });

  addTagFacets(projection);
  projection.facets.sort((left, right) => left.index.byteStart - right.index.byteStart);
  return { text: projection.text, facets: projection.facets };
}

export function markdownSourceForPost(post: PostPlan): string {
  return post.source?.format === "markdown" ? post.source.text : post.text;
}

export function projectMarkdownPost(post: PostPlan): PostPlan {
  if (post.source?.format !== "markdown") return post;
  const sourceText = markdownSourceForPost(post);
  const rawProjection = compileSocialMarkdown(sourceText);
  const leadingWhitespace = rawProjection.text.match(/^\s*/u)?.[0] ?? "";
  const text = rawProjection.text.trim();
  const leadingBytes = byteLength(leadingWhitespace);
  const finalBytes = byteLength(text);
  const facets = rawProjection.facets
    .filter(
      (facet) =>
        facet.index.byteStart >= leadingBytes &&
        facet.index.byteEnd <= leadingBytes + finalBytes
    )
    .map((facet) => ({
      ...facet,
      index: {
        byteStart: facet.index.byteStart - leadingBytes,
        byteEnd: facet.index.byteEnd - leadingBytes,
      },
    }));
  return {
    ...post,
    source: { format: "markdown", text: sourceText },
    text,
    facets: facets.length > 0 ? facets : undefined,
  };
}

function wrapSelection(
  source: string,
  selectionStart: number,
  selectionEnd: number,
  marker: string,
  placeholder: string
): MarkdownCommandResult {
  const selected = source.slice(selectionStart, selectionEnd);
  const before = source.slice(0, selectionStart);
  const after = source.slice(selectionEnd);
  if (
    selected &&
    before.endsWith(marker) &&
    after.startsWith(marker)
  ) {
    return {
      text:
        before.slice(0, -marker.length) + selected + after.slice(marker.length),
      selectionStart: selectionStart - marker.length,
      selectionEnd: selectionEnd - marker.length,
    };
  }
  const content = selected || placeholder;
  return {
    text: `${before}${marker}${content}${marker}${after}`,
    selectionStart: selectionStart + marker.length,
    selectionEnd: selectionStart + marker.length + content.length,
  };
}

function prefixSelectedLines(
  source: string,
  selectionStart: number,
  selectionEnd: number,
  prefixForIndex: (index: number) => string,
  removable: RegExp
): MarkdownCommandResult {
  const lineStart = source.lastIndexOf("\n", Math.max(selectionStart - 1, 0)) + 1;
  const nextLineBreak = source.indexOf("\n", selectionEnd);
  const lineEnd = nextLineBreak < 0 ? source.length : nextLineBreak;
  const lines = source.slice(lineStart, lineEnd).split("\n");
  const remove = lines.every((line) => removable.test(line));
  let firstDelta = 0;
  let totalDelta = 0;
  const changed = lines.map((line, index) => {
    const prefix = prefixForIndex(index);
    if (remove) {
      const next = line.replace(removable, "");
      const delta = next.length - line.length;
      if (index === 0) firstDelta = delta;
      totalDelta += delta;
      return next;
    }
    if (index === 0) firstDelta = prefix.length;
    totalDelta += prefix.length;
    return prefix + line;
  });
  return {
    text: source.slice(0, lineStart) + changed.join("\n") + source.slice(lineEnd),
    selectionStart: Math.max(lineStart, selectionStart + firstDelta),
    selectionEnd: Math.max(lineStart, selectionEnd + totalDelta),
  };
}

export function applySocialMarkdownCommand(
  source: string,
  command: SocialMarkdownCommand,
  selectionStart: number,
  selectionEnd: number
): MarkdownCommandResult {
  switch (command) {
    case "bold":
      return wrapSelection(source, selectionStart, selectionEnd, "**", "bold text");
    case "italic":
      return wrapSelection(source, selectionStart, selectionEnd, "*", "italic text");
    case "strike":
      return wrapSelection(source, selectionStart, selectionEnd, "~~", "struck text");
    case "code":
      return wrapSelection(source, selectionStart, selectionEnd, "`", "code");
    case "link": {
      const selected = source.slice(selectionStart, selectionEnd);
      const label = selected || "link text";
      const hostnamePlaceholder = "example.com";
      const insertion = `[${label}](https://${hostnamePlaceholder})`;
      const text = source.slice(0, selectionStart) + insertion + source.slice(selectionEnd);
      const hostnameStart = selectionStart + label.length + "[](https://".length;
      return {
        text,
        selectionStart: hostnameStart,
        selectionEnd: hostnameStart + hostnamePlaceholder.length,
      };
    }
    case "quote":
      return prefixSelectedLines(source, selectionStart, selectionEnd, () => "> ", /^\s*>\s?/u);
    case "unordered-list":
      return prefixSelectedLines(source, selectionStart, selectionEnd, () => "- ", /^\s*[-+*]\s+/u);
    case "ordered-list":
      return prefixSelectedLines(
        source,
        selectionStart,
        selectionEnd,
        (index) => `${index + 1}. `,
        /^\s*\d+\.\s+/u
      );
  }
}

function byteOffsetToStringIndex(text: string, byteOffset: number): number {
  if (byteOffset <= 0) return 0;
  let bytes = 0;
  let index = 0;
  for (const character of text) {
    if (bytes >= byteOffset) break;
    bytes += byteLength(character);
    index += character.length;
  }
  return index;
}

export function projectionSegments(
  projection: Pick<SocialMarkdownProjection, "text" | "facets">
): ProjectionSegment[] {
  const links = projection.facets
    .map((facet) => {
      const feature = facet.features.find(
        (candidate) => candidate.$type === "app.bsky.richtext.facet#link"
      );
      return feature?.$type === "app.bsky.richtext.facet#link"
        ? { ...facet.index, uri: feature.uri }
        : null;
    })
    .filter((link): link is { byteStart: number; byteEnd: number; uri: string } => link !== null)
    .sort((left, right) => left.byteStart - right.byteStart);
  const segments: ProjectionSegment[] = [];
  let cursor = 0;
  for (const link of links) {
    const start = byteOffsetToStringIndex(projection.text, link.byteStart);
    const end = byteOffsetToStringIndex(projection.text, link.byteEnd);
    if (start < cursor || end <= start) continue;
    if (start > cursor) segments.push({ text: projection.text.slice(cursor, start) });
    segments.push({ text: projection.text.slice(start, end), uri: link.uri });
    cursor = end;
  }
  if (cursor < projection.text.length) segments.push({ text: projection.text.slice(cursor) });
  return segments;
}
