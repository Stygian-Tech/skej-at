"use client";

import {
  Code2,
  FileCode2,
  Link2,
} from "lucide-react";
import * as React from "react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  SocialMarkdownCommand,
  applySocialMarkdownCommand,
  markdownSourceForPost,
  projectMarkdownPost,
  projectionSegments,
} from "@/lib/socialMarkdown";
import type { PostPlan } from "@/lib/skejTypes";
import { cn } from "@/lib/utils";

interface SocialMarkdownEditorProps {
  index: number;
  post: PostPlan;
  onChange: (post: PostPlan) => void;
}

interface SocialMarkdownPreviewProps extends React.HTMLAttributes<HTMLDivElement> {
  post: PostPlan;
  emptyMessage?: string;
}

const COMMANDS: Array<{
  command: SocialMarkdownCommand;
  label: string;
  icon: typeof Code2;
  shortcut?: string;
}> = [
  { command: "link", label: "Link", icon: Link2, shortcut: "⌘K" },
  { command: "code", label: "Monospace", icon: Code2, shortcut: "⌘E" },
  { command: "code-block", label: "Code block", icon: FileCode2 },
];

function shortcutCommand(event: React.KeyboardEvent<HTMLTextAreaElement>) {
  if (!(event.metaKey || event.ctrlKey) || event.altKey) return null;
  const key = event.key.toLowerCase();
  if (key === "b" && !event.shiftKey) return "bold";
  if (key === "i" && !event.shiftKey) return "italic";
  if (key === "s" && event.shiftKey) return "strike";
  if (key === "e" && !event.shiftKey) return "code";
  if (key === "k" && !event.shiftKey) return "link";
  return null;
}

function renderInlineCode(text: string, keyPrefix: string): React.ReactNode[] {
  const nodes: React.ReactNode[] = [];
  let cursor = 0;
  let token = 0;
  while (cursor < text.length) {
    const opening = text.indexOf("`", cursor);
    const closing = opening >= 0 ? text.indexOf("`", opening + 1) : -1;
    if (opening < 0 || closing <= opening + 1) {
      nodes.push(text.slice(cursor));
      break;
    }
    if (opening > cursor) nodes.push(text.slice(cursor, opening));
    nodes.push(
      <code
        className="rounded-md bg-muted px-1.5 py-0.5 font-mono text-[0.92em] font-semibold"
        key={`${keyPrefix}-inline-${token}`}
      >
        {text.slice(opening + 1, closing)}
      </code>
    );
    cursor = closing + 1;
    token += 1;
  }
  return nodes;
}

function renderCodePresentation(text: string, keyPrefix: string): React.ReactNode[] {
  const nodes: React.ReactNode[] = [];
  const lines = text.split("\n");
  let prose: string[] = [];
  let code: string[] = [];
  let fence: "```" | "~~~" | null = null;
  let token = 0;
  const flushProse = () => {
    if (prose.length === 0) return;
    const value = prose.join("\n");
    nodes.push(
      <React.Fragment key={`${keyPrefix}-prose-${token}`}>
        {renderInlineCode(value, `${keyPrefix}-${token}`)}
      </React.Fragment>
    );
    prose = [];
    token += 1;
  };
  const flushCode = () => {
    nodes.push(
      <pre
        className="my-2 overflow-x-auto rounded-xl bg-muted px-3 py-2 font-mono text-sm font-semibold leading-6"
        key={`${keyPrefix}-block-${token}`}
      >
        <code>{code.join("\n")}</code>
      </pre>
    );
    code = [];
    token += 1;
  };

  for (const line of lines) {
    const trimmed = line.trim();
    const delimiter = trimmed.startsWith("```")
      ? "```"
      : trimmed.startsWith("~~~")
        ? "~~~"
        : null;
    if (fence) {
      if (delimiter === fence) {
        flushCode();
        fence = null;
      } else code.push(line);
    } else if (delimiter) {
      flushProse();
      fence = delimiter;
    } else prose.push(line);
  }
  if (fence) {
    prose.push(fence, ...code);
    code = [];
  }
  flushProse();
  return nodes;
}

export function SocialMarkdownPreview({
  post,
  className,
  emptyMessage = "Nothing to preview yet.",
  ...props
}: SocialMarkdownPreviewProps) {
  const projection = projectMarkdownPost(post);
  const segments = projectionSegments({
    text: projection.text,
    facets: projection.facets ?? [],
  });
  return (
    <div className={cn("whitespace-pre-wrap break-words", className)} {...props}>
      {projection.text ? (
        segments.map((segment, segmentIndex) =>
          segment.uri ? (
            <a
              className="text-primary underline decoration-primary/40 underline-offset-2"
              href={segment.uri}
              key={`${segmentIndex}-${segment.uri}`}
              rel="noreferrer noopener"
              target="_blank"
            >
              {segment.text}
            </a>
          ) : (
            <React.Fragment key={segmentIndex}>
              {renderCodePresentation(segment.text, `segment-${segmentIndex}`)}
            </React.Fragment>
          )
        )
      ) : (
        <span className="text-muted-foreground">{emptyMessage}</span>
      )}
    </div>
  );
}

export const SocialMarkdownEditor = React.memo(function SocialMarkdownEditor({
  index,
  post,
  onChange,
}: SocialMarkdownEditorProps) {
  const textareaRef = React.useRef<HTMLTextAreaElement>(null);
  const pendingSelection = React.useRef<{ start: number; end: number } | null>(null);
  const source = markdownSourceForPost(post);
  const projection = React.useMemo(() => projectMarkdownPost(post), [post]);

  React.useLayoutEffect(() => {
    const selection = pendingSelection.current;
    if (!selection || !textareaRef.current) return;
    pendingSelection.current = null;
    const restore = () => {
      textareaRef.current?.focus();
      textareaRef.current?.setSelectionRange(selection.start, selection.end);
    };
    if (typeof requestAnimationFrame === "function") requestAnimationFrame(restore);
    else restore();
  }, [source]);

  const updateSource = React.useCallback(
    (text: string) => {
      onChange(
        projectMarkdownPost({
          ...post,
          source: { format: "markdown", text },
        })
      );
    },
    [onChange, post]
  );

  const applyCommand = React.useCallback(
    (command: SocialMarkdownCommand) => {
      const textarea = textareaRef.current;
      const start = textarea?.selectionStart ?? source.length;
      const end = textarea?.selectionEnd ?? start;
      const result = applySocialMarkdownCommand(source, command, start, end);
      pendingSelection.current = {
        start: result.selectionStart,
        end: result.selectionEnd,
      };
      updateSource(result.text);
    },
    [source, updateSource]
  );

  return (
    <div className="grid min-w-0 gap-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs font-black text-foreground">Markdown</span>
        <span className="text-xs font-semibold text-muted-foreground">
          Links publish natively. Monospace and code blocks have limited client support.
        </span>
      </div>

      <div className="grid min-w-0 gap-2">
        <div aria-label="Markdown formatting" className="flex flex-wrap gap-1" role="toolbar">
          {COMMANDS.map(({ command, label, icon: Icon, shortcut }) => (
            <Button
              aria-label={label}
              key={command}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => applyCommand(command)}
              size="icon"
              title={shortcut ? `${label} (${shortcut})` : label}
              type="button"
              variant="ghost"
            >
              <Icon />
            </Button>
          ))}
        </div>
        <Textarea
          aria-describedby={`post-${index + 1}-bluesky-output-label`}
          aria-label={`Post ${index + 1} Markdown`}
          onChange={(event) => updateSource(event.target.value)}
          onKeyDown={(event) => {
            const command = shortcutCommand(event);
            if (!command) return;
            event.preventDefault();
            applyCommand(command);
          }}
          placeholder="What should future-you say? Markdown links and lightweight formatting are supported."
          ref={textareaRef}
          value={source}
        />
      </div>

      <div className="grid min-w-0 gap-1.5">
        <div
          className="flex flex-wrap items-center justify-between gap-2 px-1 text-xs font-semibold text-muted-foreground"
          id={`post-${index + 1}-bluesky-output-label`}
        >
          <span className="font-black text-foreground">Bluesky output</span>
          <span>Rendered here; code presentation depends on the client.</span>
        </div>
        <SocialMarkdownPreview
          aria-labelledby={`post-${index + 1}-bluesky-output-label`}
          className="min-h-16 whitespace-pre-wrap break-words rounded-[1.25rem] border border-input bg-card px-4 py-3 text-base font-semibold leading-7"
          emptyMessage="Your published text will appear here."
          id={`post-${index + 1}-bluesky-output`}
          post={projection}
        />
      </div>
    </div>
  );
});
