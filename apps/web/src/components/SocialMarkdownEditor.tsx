"use client";

import {
  Bold,
  Code2,
  Italic,
  Link2,
  List,
  ListOrdered,
  Quote,
  Strikethrough,
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
  icon: typeof Bold;
  shortcut?: string;
}> = [
  { command: "bold", label: "Bold", icon: Bold, shortcut: "⌘B" },
  { command: "italic", label: "Italic", icon: Italic, shortcut: "⌘I" },
  { command: "strike", label: "Strikethrough", icon: Strikethrough, shortcut: "⌘⇧S" },
  { command: "code", label: "Inline code", icon: Code2, shortcut: "⌘E" },
  { command: "link", label: "Link", icon: Link2, shortcut: "⌘K" },
  { command: "quote", label: "Blockquote", icon: Quote },
  { command: "unordered-list", label: "Bulleted list", icon: List },
  { command: "ordered-list", label: "Numbered list", icon: ListOrdered },
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
            <React.Fragment key={segmentIndex}>{segment.text}</React.Fragment>
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
          Links must start with http:// or https://.
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
          <span>Formatting is projected inline; links stay clickable.</span>
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
