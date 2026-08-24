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

type EditorMode = "write" | "preview";

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
  const [mode, setMode] = React.useState<EditorMode>("write");
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
        <div
          aria-label={`Post ${index + 1} editor mode`}
          className="flex rounded-full bg-muted p-1"
          role="tablist"
        >
          {(["write", "preview"] as const).map((item) => (
            <button
              aria-controls={`post-${index + 1}-${item}`}
              aria-selected={mode === item}
              className={cn(
                "min-h-9 rounded-full px-3 text-xs font-black capitalize transition",
                mode === item ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"
              )}
              id={`post-${index + 1}-${item}-tab`}
              key={item}
              onClick={() => setMode(item)}
              role="tab"
              type="button"
            >
              {item}
            </button>
          ))}
        </div>
        <span className="text-xs font-semibold text-muted-foreground">
          Preview is the exact Bluesky text.
        </span>
      </div>

      {mode === "write" ? (
        <div
          aria-labelledby={`post-${index + 1}-write-tab`}
          className="grid min-w-0 gap-2"
          id={`post-${index + 1}-write`}
          role="tabpanel"
        >
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
      ) : (
        <SocialMarkdownPreview
          aria-labelledby={`post-${index + 1}-preview-tab`}
          className="min-h-28 whitespace-pre-wrap break-words rounded-[1.5rem] border border-input bg-card px-4 py-3 text-base font-semibold leading-7"
          emptyMessage="Nothing to preview yet."
          id={`post-${index + 1}-preview`}
          post={projection}
          role="tabpanel"
        />
      )}
    </div>
  );
});
