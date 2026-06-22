"use client";

import {
  AlertCircle,
  ArrowUpRight,
  CalendarClock,
  CheckCircle2,
  Clock3,
  Cloud,
  ImagePlus,
  Link2,
  ListRestart,
  Loader2,
  LockKeyhole,
  LogOut,
  MessageCircleReply,
  Pencil,
  Plus,
  Quote,
  RefreshCw,
  Send,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import Link from "next/link";
import * as React from "react";

import { OAuthLoginForm } from "@/components/OAuthLoginForm";
import { ThemeToggle } from "@/components/ThemeToggle";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  createSchedule,
  deleteSchedule,
  getViewer,
  listSchedules,
  logout,
  publishNow,
  updateSchedule,
} from "@/lib/api";
import {
  ComposerDraft,
  MAX_POST_GRAPHEMES,
  countGraphemes,
  localDatetimeValue,
  validateComposerDraft,
} from "@/lib/editor";
import { cn } from "@/lib/utils";
import { PostPlan, ScheduledPostSummary, Viewer } from "@/lib/skejTypes";

type AuthStatus = "loading" | "anonymous" | "authenticated";

function defaultScheduleDate(minutes = 180) {
  return new Date(Date.now() + minutes * 60_000);
}

function emptyDraft(date = defaultScheduleDate()): ComposerDraft {
  return {
    mode: "post",
    scheduledFor: localDatetimeValue(date),
    posts: [
      {
        text: "",
        langs: ["en"],
        tags: [],
      },
    ],
  };
}

function hydrationSafeDraft(): ComposerDraft {
  return {
    mode: "post",
    scheduledFor: "",
    posts: [{ text: "", langs: ["en"], tags: [] }],
  };
}

function draftFromSchedule(
  item: ScheduledPostSummary,
  date = new Date(item.scheduledFor)
): ComposerDraft {
  const first = item.record.posts[0];
  return {
    mode: first?.reply ? "reply" : first?.embed?.record ? "quote" : "post",
    scheduledFor: localDatetimeValue(date),
    posts: item.record.posts.map((post) => ({
      ...post,
      embed: post.embed ? { ...post.embed } : undefined,
    })),
    contentWarning: first?.labels?.[0],
  };
}

function statusVariant(status: ScheduledPostSummary["status"]) {
  switch (status) {
    case "scheduled":
      return "secondary";
    case "publishing":
      return "warning";
    case "published":
      return "success";
    case "failed":
      return "failed";
    case "cancelled":
      return "outline";
  }
}

function formatSchedule(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

function upsertQueueItem(
  queue: ScheduledPostSummary[],
  item: ScheduledPostSummary
): ScheduledPostSummary[] {
  const exists = queue.some((entry) => entry.rkey === item.rkey);
  if (!exists) return [item, ...queue];
  return queue.map((entry) => (entry.rkey === item.rkey ? item : entry));
}

function splitCSV(value: string) {
  return value
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function firstInitial(viewer: Viewer | null) {
  return (viewer?.displayName ?? viewer?.handle ?? "S").charAt(0).toUpperCase();
}

export function SkejApp() {
  const [authStatus, setAuthStatus] = React.useState<AuthStatus>("loading");
  const [viewer, setViewer] = React.useState<Viewer | null>(null);
  const [draft, setDraft] = React.useState<ComposerDraft>(() => hydrationSafeDraft());
  const [queue, setQueue] = React.useState<ScheduledPostSummary[]>([]);
  const [scheduleOpen, setScheduleOpen] = React.useState(false);
  const [selectedRkey, setSelectedRkey] = React.useState<string | null>(null);
  const [editingRkey, setEditingRkey] = React.useState<string | null>(null);
  const [isQueueLoading, setIsQueueLoading] = React.useState(false);
  const [isMutating, setIsMutating] = React.useState(false);
  const [actionError, setActionError] = React.useState<string | null>(null);
  const [actionMessage, setActionMessage] = React.useState<string | null>(null);

  const issues = React.useMemo(() => validateComposerDraft(draft), [draft]);
  const firstPostCount = countGraphemes(draft.posts[0]?.text ?? "");
  const selected = queue.find((item) => item.rkey === selectedRkey) ?? queue[0] ?? null;
  const isAuthenticated = authStatus === "authenticated" && viewer !== null;

  const refreshSchedules = React.useCallback(async () => {
    setIsQueueLoading(true);
    try {
      const records = await listSchedules();
      setQueue(records);
      setSelectedRkey((current) =>
        current && records.some((record) => record.rkey === current)
          ? current
          : records[0]?.rkey ?? null
      );
    } finally {
      setIsQueueLoading(false);
    }
  }, []);

  React.useEffect(() => {
    let cancelled = false;
    const draftTimer = window.setTimeout(() => {
      if (!cancelled) setDraft(emptyDraft());
    }, 0);

    async function loadSession() {
      try {
        const currentViewer = await getViewer();
        if (cancelled) return;
        setViewer(currentViewer);
        setAuthStatus("authenticated");
        await refreshSchedules();
      } catch (error) {
        if (cancelled) return;
        setViewer(null);
        setQueue([]);
        setSelectedRkey(null);
        setAuthStatus("anonymous");
        if (error instanceof Error && !error.message.toLowerCase().includes("sign in")) {
          setActionError(error.message);
        }
      }
    }

    void loadSession();
    return () => {
      cancelled = true;
      window.clearTimeout(draftTimer);
    };
  }, [refreshSchedules]);

  function updatePost(index: number, text: string) {
    setDraft((current) => ({
      ...current,
      posts: current.posts.map((post, postIndex) =>
        postIndex === index ? { ...post, text } : post
      ),
    }));
  }

  function updateFirstPost(updater: (post: PostPlan) => PostPlan) {
    setDraft((current) => {
      const [first = { text: "", langs: ["en"], tags: [] }, ...rest] = current.posts;
      return {
        ...current,
        posts: [updater(first), ...rest],
      };
    });
  }

  function addThreadPost() {
    setDraft((current) => ({
      ...current,
      posts: [
        ...current.posts,
        {
          text: "",
          langs: ["en"],
          tags: [],
        },
      ],
    }));
  }

  function removeThreadPost(index: number) {
    setDraft((current) => ({
      ...current,
      posts: current.posts.filter((_, postIndex) => postIndex !== index),
    }));
  }

  function resetComposer() {
    setDraft(emptyDraft());
    setEditingRkey(null);
  }

  async function scheduleDraft() {
    setActionError(null);
    setActionMessage(null);
    const validation = validateComposerDraft(draft);
    if (validation.length > 0) {
      setActionError(validation[0]?.message ?? "Fix the composer before scheduling.");
      return;
    }
    setIsMutating(true);
    try {
      const item = editingRkey
        ? await updateSchedule(editingRkey, draft)
        : await createSchedule(draft);
      setQueue((current) => upsertQueueItem(current, item));
      setSelectedRkey(item.rkey);
      setActionMessage(editingRkey ? "Schedule updated." : "Post scheduled.");
      resetComposer();
      setScheduleOpen(false);
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Could not schedule post.");
    } finally {
      setIsMutating(false);
    }
  }

  async function retryPost(item: ScheduledPostSummary) {
    setIsMutating(true);
    setActionError(null);
    try {
      const updated = await updateSchedule(
        item.rkey,
        draftFromSchedule(item, defaultScheduleDate(15))
      );
      setQueue((current) => upsertQueueItem(current, updated));
      setSelectedRkey(updated.rkey);
      setActionMessage("Post rescheduled for retry.");
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Could not retry post.");
    } finally {
      setIsMutating(false);
    }
  }

  async function deletePost(rkey: string) {
    setIsMutating(true);
    setActionError(null);
    try {
      await deleteSchedule(rkey);
      setQueue((current) => current.filter((entry) => entry.rkey !== rkey));
      setSelectedRkey((current) => (current === rkey ? null : current));
      if (editingRkey === rkey) resetComposer();
      setActionMessage("Schedule deleted.");
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Could not delete schedule.");
    } finally {
      setIsMutating(false);
    }
  }

  async function publishSelected(item: ScheduledPostSummary) {
    setIsMutating(true);
    setActionError(null);
    try {
      const published = await publishNow(item.rkey);
      setQueue((current) => upsertQueueItem(current, published));
      setSelectedRkey(published.rkey);
      setActionMessage("Post published.");
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Could not publish post.");
    } finally {
      setIsMutating(false);
    }
  }

  async function signOut() {
    setIsMutating(true);
    try {
      await logout();
      setViewer(null);
      setQueue([]);
      setSelectedRkey(null);
      setAuthStatus("anonymous");
      resetComposer();
    } finally {
      setIsMutating(false);
    }
  }

  function editSchedule(item: ScheduledPostSummary) {
    setDraft(draftFromSchedule(item));
    setEditingRkey(item.rkey);
    setActionMessage("Loaded schedule into the composer.");
    document.getElementById("composer")?.scrollIntoView({ behavior: "smooth" });
  }

  return (
    <main className="min-h-dvh overflow-hidden px-4 pb-28 pt-4 text-foreground sm:px-6 lg:px-8 lg:pb-4">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-5">
        <header className="flex items-center justify-between gap-3 rounded-[2rem] border border-border bg-card/80 px-4 py-3 shadow-[0_20px_60px_rgba(70,52,70,0.1)] backdrop-blur">
          <Link className="flex min-w-0 items-center gap-3" href="/">
            <div className="grid size-12 shrink-0 place-items-center rounded-2xl bg-primary text-xl font-black text-primary-foreground shadow-[0_14px_30px_rgba(255,79,109,0.22)]">
              S
            </div>
            <div className="flex min-w-0 flex-col">
              <div className="flex items-center gap-2">
                <span className="text-2xl font-black text-primary">Skej</span>
                <Badge variant="sunny">Alpha</Badge>
              </div>
              <span className="truncate text-xs font-bold text-muted-foreground">
                Schedule posts from your PDS
              </span>
            </div>
          </Link>
          <div className="flex items-center gap-2">
            <ThemeToggle />
            {isAuthenticated ? (
              <div className="flex items-center gap-2 rounded-full border border-border bg-card py-1 pl-1 pr-2">
                <div className="grid size-8 place-items-center rounded-full bg-secondary text-sm font-black text-secondary-foreground">
                  {firstInitial(viewer)}
                </div>
                <div className="hidden flex-col text-right sm:flex">
                  <span className="text-xs font-black">{viewer.displayName ?? "Skej user"}</span>
                  <span className="text-xs text-muted-foreground">@{viewer.handle}</span>
                </div>
                <Button
                  aria-label="Log out"
                  disabled={isMutating}
                  onClick={signOut}
                  size="icon"
                  variant="ghost"
                >
                  <LogOut />
                </Button>
              </div>
            ) : (
              <Button
                size="sm"
                onClick={() => {
                  window.location.href = "/oauth/start?handle=skej.demo";
                }}
              >
                <LockKeyhole data-icon="inline-start" />
                Connect
              </Button>
            )}
          </div>
        </header>

        <Card className="border-border bg-card/90">
          <CardContent className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
            <div className="flex items-start gap-3">
              <div className="grid size-11 shrink-0 place-items-center rounded-2xl bg-primary text-primary-foreground shadow-[0_14px_30px_rgba(255,79,109,0.18)]">
                <Sparkles />
              </div>
              <div className="flex min-w-0 flex-col gap-1">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="sunny">Alpha</Badge>
                  <h2 className="text-base font-black leading-tight sm:text-lg">
                    Skej is still getting tuned.
                  </h2>
                </div>
                <p className="max-w-2xl text-sm font-semibold leading-6 text-muted-foreground">
                  Scheduling uses OAuth app sessions and a SQLite queue while the
                  production PDS integration hardens up. Keep a copy of anything
                  mission-critical for now.
                </p>
              </div>
            </div>
            <div className="flex flex-wrap gap-2 text-xs font-black text-secondary-foreground sm:justify-end">
              <span className="rounded-full border border-border bg-secondary px-3 py-1.5">
                OAuth session
              </span>
              <span className="rounded-full border border-border bg-secondary px-3 py-1.5">
                SQLite queue
              </span>
            </div>
          </CardContent>
        </Card>

        {actionError ? (
          <div className="flex items-start gap-3 rounded-[1.5rem] border border-destructive/30 bg-muted px-4 py-3 text-sm font-bold text-destructive">
            <AlertCircle className="mt-0.5 shrink-0" />
            {actionError}
          </div>
        ) : null}
        {actionMessage ? (
          <div className="flex items-start gap-3 rounded-[1.5rem] border border-border bg-secondary px-4 py-3 text-sm font-bold text-secondary-foreground">
            <CheckCircle2 className="mt-0.5 shrink-0" />
            {actionMessage}
          </div>
        ) : null}

        <section className="grid gap-5 lg:grid-cols-[minmax(0,1.05fr)_minmax(360px,0.75fr)]">
          <div className="flex flex-col gap-5">
            {authStatus === "loading" ? (
              <Card>
                <CardContent className="flex items-center gap-3 p-5 text-sm font-bold text-muted-foreground">
                  <Loader2 className="animate-spin" />
                  Checking your Skej session...
                </CardContent>
              </Card>
            ) : null}

            {!isAuthenticated && authStatus !== "loading" ? (
              <Card className="overflow-hidden">
                <CardHeader>
                  <CardTitle>Connect your PDS</CardTitle>
                  <CardDescription>
                    Start OAuth to create an app session, then Skej can list and manage
                    your scheduled posts.
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                  <OAuthLoginForm compact defaultHandle="skej.demo" />
                </CardContent>
              </Card>
            ) : null}

            {isAuthenticated ? (
              <Card className="relative overflow-hidden" id="composer">
                <CardHeader className="relative">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <CardTitle className="text-2xl">
                        {editingRkey ? "Edit schedule" : "Compose"}
                      </CardTitle>
                      <CardDescription>
                        Build a post, thread, reply, or quote and send it later.
                      </CardDescription>
                    </div>
                    <Badge variant="sunny">
                      {editingRkey ? `Editing ${editingRkey}` : "Public post plan"}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent className="relative flex flex-col gap-4">
                  <div className="rounded-[1.25rem] border border-border bg-muted p-3 sm:rounded-[1.5rem] sm:p-4">
                    <div className="flex gap-3">
                      <AlertCircle className="mt-0.5 shrink-0 text-primary" />
                      <p className="text-xs font-semibold leading-5 text-muted-foreground sm:text-sm sm:leading-6">
                        Scheduled content is stored in the alpha queue until the worker
                        publishes it as an <span className="font-black">app.bsky.feed.post</span>.
                      </p>
                    </div>
                  </div>

                  <div className="grid grid-cols-3 gap-2">
                    {[
                      { mode: "post", label: "Post", icon: Send },
                      { mode: "reply", label: "Reply", icon: MessageCircleReply },
                      { mode: "quote", label: "Quote", icon: Quote },
                    ].map((item) => {
                      const Icon = item.icon;
                      return (
                        <button
                          key={item.mode}
                          type="button"
                          className={cn(
                            "flex min-h-11 items-center justify-center gap-2 rounded-full border text-sm font-black transition sm:min-h-12",
                            draft.mode === item.mode
                              ? "border-primary bg-primary text-primary-foreground shadow-[0_12px_24px_rgba(255,79,109,0.2)]"
                              : "border-border bg-card text-muted-foreground hover:bg-muted"
                          )}
                          onClick={() =>
                            setDraft((current) => ({
                              ...current,
                              mode: item.mode as ComposerDraft["mode"],
                            }))
                          }
                        >
                          <Icon />
                          {item.label}
                        </button>
                      );
                    })}
                  </div>

                  <div className="flex flex-col gap-3">
                    {draft.posts.map((post, index) => {
                      const count = countGraphemes(post.text);
                      return (
                        <div
                          key={index}
                          className="flex flex-col gap-2 rounded-[1.25rem] border border-border bg-background/60 p-2.5 sm:rounded-[1.5rem] sm:p-3"
                        >
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-sm font-black">
                              {draft.posts.length > 1 ? `Post ${index + 1}` : "Post"}
                            </span>
                            <div className="flex items-center gap-2">
                              <span
                                className={cn(
                                  "text-xs font-black",
                                  count > MAX_POST_GRAPHEMES
                                    ? "text-destructive"
                                    : "text-muted-foreground"
                                )}
                              >
                                {count}/{MAX_POST_GRAPHEMES}
                              </span>
                              {draft.posts.length > 1 ? (
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  aria-label={`Remove post ${index + 1}`}
                                  onClick={() => removeThreadPost(index)}
                                >
                                  <X />
                                </Button>
                              ) : null}
                            </div>
                          </div>
                          <Textarea
                            value={post.text}
                            onChange={(event) => updatePost(index, event.target.value)}
                            placeholder="What should future-you say?"
                            aria-label={`Post ${index + 1} text`}
                          />
                        </div>
                      );
                    })}
                  </div>

                  {draft.mode === "reply" ? (
                    <div className="grid gap-3 rounded-[1.25rem] border border-border bg-card p-3 sm:grid-cols-2">
                      <Input
                        aria-label="Reply root URI"
                        placeholder="Root post URI"
                        value={draft.posts[0]?.reply?.root.uri ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => {
                            const reply = post.reply ?? {
                              root: { uri: "", cid: "" },
                              parent: { uri: "", cid: "" },
                            };
                            return {
                              ...post,
                              reply: {
                                ...reply,
                                root: { ...reply.root, uri: event.target.value },
                              },
                            };
                          })
                        }
                      />
                      <Input
                        aria-label="Reply root CID"
                        placeholder="Root CID"
                        value={draft.posts[0]?.reply?.root.cid ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => {
                            const reply = post.reply ?? {
                              root: { uri: "", cid: "" },
                              parent: { uri: "", cid: "" },
                            };
                            return {
                              ...post,
                              reply: {
                                ...reply,
                                root: { ...reply.root, cid: event.target.value },
                              },
                            };
                          })
                        }
                      />
                      <Input
                        aria-label="Reply parent URI"
                        placeholder="Parent post URI"
                        value={draft.posts[0]?.reply?.parent.uri ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => {
                            const reply = post.reply ?? {
                              root: { uri: "", cid: "" },
                              parent: { uri: "", cid: "" },
                            };
                            return {
                              ...post,
                              reply: {
                                ...reply,
                                parent: { ...reply.parent, uri: event.target.value },
                              },
                            };
                          })
                        }
                      />
                      <Input
                        aria-label="Reply parent CID"
                        placeholder="Parent CID"
                        value={draft.posts[0]?.reply?.parent.cid ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => {
                            const reply = post.reply ?? {
                              root: { uri: "", cid: "" },
                              parent: { uri: "", cid: "" },
                            };
                            return {
                              ...post,
                              reply: {
                                ...reply,
                                parent: { ...reply.parent, cid: event.target.value },
                              },
                            };
                          })
                        }
                      />
                    </div>
                  ) : null}

                  {draft.mode === "quote" ? (
                    <div className="grid gap-3 rounded-[1.25rem] border border-border bg-card p-3 sm:grid-cols-2">
                      <Input
                        aria-label="Quote post URI"
                        placeholder="Quoted post URI"
                        value={draft.posts[0]?.embed?.record?.uri ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => ({
                            ...post,
                            embed: {
                              ...post.embed,
                              record: {
                                uri: event.target.value,
                                cid: post.embed?.record?.cid ?? "",
                              },
                            },
                          }))
                        }
                      />
                      <Input
                        aria-label="Quote post CID"
                        placeholder="Quoted post CID"
                        value={draft.posts[0]?.embed?.record?.cid ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => ({
                            ...post,
                            embed: {
                              ...post.embed,
                              record: {
                                uri: post.embed?.record?.uri ?? "",
                                cid: event.target.value,
                              },
                            },
                          }))
                        }
                      />
                    </div>
                  ) : null}

                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                    <Button variant="outline" onClick={addThreadPost}>
                      <Plus data-icon="inline-start" />
                      Thread
                    </Button>
                    <Button
                      variant="outline"
                      onClick={() =>
                        updateFirstPost((post) => ({
                          ...post,
                          embed: {
                            ...post.embed,
                            images: [
                              ...(post.embed?.images ?? []),
                              {
                                id: `draft-image-${Date.now()}`,
                                alt: "",
                                previewUrl: "/icon.png",
                              },
                            ],
                          },
                        }))
                      }
                    >
                      <ImagePlus data-icon="inline-start" />
                      Images
                    </Button>
                    <Button
                      variant="outline"
                      onClick={() =>
                        updateFirstPost((post) => ({
                          ...post,
                          embed: {
                            ...post.embed,
                            external: post.embed?.external ?? {
                              uri: "https://skej.at",
                              title: "Skej",
                              description: "Schedule posts from your PDS.",
                            },
                          },
                        }))
                      }
                    >
                      <Link2 data-icon="inline-start" />
                      Link card
                    </Button>
                    <Button
                      variant="outline"
                      onClick={() =>
                        setDraft((current) => ({
                          ...current,
                          contentWarning: current.contentWarning ? undefined : "warn",
                        }))
                      }
                    >
                      <Sparkles data-icon="inline-start" />
                      Warning
                    </Button>
                  </div>

                  {draft.posts[0]?.embed?.external ? (
                    <div className="grid gap-3 rounded-[1.25rem] border border-border bg-card p-3">
                      <Input
                        aria-label="External URL"
                        placeholder="https://example.com"
                        value={draft.posts[0].embed.external.uri}
                        onChange={(event) =>
                          updateFirstPost((post) => ({
                            ...post,
                            embed: {
                              ...post.embed,
                              external: {
                                ...(post.embed?.external ?? { uri: "" }),
                                uri: event.target.value,
                              },
                            },
                          }))
                        }
                      />
                      <div className="grid gap-3 sm:grid-cols-2">
                        <Input
                          aria-label="External title"
                          placeholder="Link title"
                          value={draft.posts[0].embed.external.title ?? ""}
                          onChange={(event) =>
                            updateFirstPost((post) => ({
                              ...post,
                              embed: {
                                ...post.embed,
                                external: {
                                  ...(post.embed?.external ?? { uri: "" }),
                                  title: event.target.value,
                                },
                              },
                            }))
                          }
                        />
                        <Input
                          aria-label="External description"
                          placeholder="Link description"
                          value={draft.posts[0].embed.external.description ?? ""}
                          onChange={(event) =>
                            updateFirstPost((post) => ({
                              ...post,
                              embed: {
                                ...post.embed,
                                external: {
                                  ...(post.embed?.external ?? { uri: "" }),
                                  description: event.target.value,
                                },
                              },
                            }))
                          }
                        />
                      </div>
                    </div>
                  ) : null}

                  {draft.posts[0]?.embed?.images?.length ? (
                    <div className="grid gap-3 sm:grid-cols-2">
                      {draft.posts[0].embed.images.map((image) => (
                        <label
                          className="flex flex-col gap-2 rounded-[1.25rem] border border-border bg-secondary/60 p-3"
                          key={image.id}
                        >
                          <span className="text-sm font-black">Alt text</span>
                          <Input
                            value={image.alt}
                            onChange={(event) =>
                              updateFirstPost((post) => ({
                                ...post,
                                embed: {
                                  ...post.embed,
                                  images: post.embed?.images?.map((entry) =>
                                    entry.id === image.id
                                      ? { ...entry, alt: event.target.value }
                                      : entry
                                  ),
                                },
                              }))
                            }
                          />
                        </label>
                      ))}
                    </div>
                  ) : null}

                  <div className="grid gap-3 sm:grid-cols-2">
                    <label className="flex flex-col gap-2">
                      <span className="text-sm font-black">Languages</span>
                      <Input
                        value={draft.posts[0]?.langs?.join(", ") ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => ({
                            ...post,
                            langs: splitCSV(event.target.value),
                          }))
                        }
                        placeholder="en"
                      />
                    </label>
                    <label className="flex flex-col gap-2">
                      <span className="text-sm font-black">Tags</span>
                      <Input
                        value={draft.posts[0]?.tags?.join(", ") ?? ""}
                        onChange={(event) =>
                          updateFirstPost((post) => ({
                            ...post,
                            tags: splitCSV(event.target.value),
                          }))
                        }
                        placeholder="skej, launch"
                      />
                    </label>
                  </div>

                  <div className="grid gap-3 sm:grid-cols-[1fr_auto]">
                    <label className="flex flex-col gap-2">
                      <span className="text-sm font-black">Schedule</span>
                      <Input
                        type="datetime-local"
                        value={draft.scheduledFor}
                        onChange={(event) =>
                          setDraft((current) => ({
                            ...current,
                            scheduledFor: event.target.value,
                          }))
                        }
                      />
                    </label>
                    <div className="flex items-end gap-2">
                      {editingRkey ? (
                        <Button variant="outline" onClick={resetComposer}>
                          <X data-icon="inline-start" />
                          Cancel
                        </Button>
                      ) : null}
                      <Button
                        size="lg"
                        className="w-full sm:w-auto"
                        disabled={issues.length > 0 || isMutating}
                        onClick={scheduleDraft}
                      >
                        {isMutating ? (
                          <Loader2 className="animate-spin" data-icon="inline-start" />
                        ) : (
                          <CalendarClock data-icon="inline-start" />
                        )}
                        {editingRkey ? "Save update" : "Schedule"}
                      </Button>
                    </div>
                  </div>

                  {issues.length > 0 ? (
                    <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                      {issues[0]?.message}
                    </div>
                  ) : (
                    <div className="flex items-center gap-2 rounded-2xl bg-secondary px-4 py-3 text-sm font-black text-secondary-foreground">
                      <CheckCircle2 />
                      Ready for {formatSchedule(new Date(draft.scheduledFor).toISOString())}
                    </div>
                  )}
                </CardContent>
              </Card>
            ) : null}
          </div>

          <nav className="sticky bottom-[max(0.5rem,env(safe-area-inset-bottom))] z-10 rounded-full border border-border bg-card/95 p-1.5 shadow-[0_18px_50px_rgba(70,52,70,0.18)] backdrop-blur lg:hidden">
            <div className="grid grid-cols-3 gap-2">
              <Button
                variant="default"
                size="sm"
                onClick={() =>
                  document.getElementById("composer")?.scrollIntoView({ behavior: "smooth" })
                }
              >
                <Send data-icon="inline-start" />
                Compose
              </Button>
              <Button variant="secondary" size="sm" onClick={() => setScheduleOpen(true)}>
                <ListRestart data-icon="inline-start" />
                Queue
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={isAuthenticated ? signOut : undefined}
              >
                <LockKeyhole data-icon="inline-start" />
                OAuth
              </Button>
            </div>
          </nav>

          <aside className="flex flex-col gap-5">
            <Card className="overflow-hidden">
              <CardHeader>
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <CardTitle>Queue</CardTitle>
                    <CardDescription>
                      {isQueueLoading ? "Refreshing..." : `${queue.length} scheduled records`}
                    </CardDescription>
                  </div>
                  <Button
                    variant="secondary"
                    size="icon"
                    aria-label="Refresh queue"
                    onClick={refreshSchedules}
                    disabled={!isAuthenticated || isQueueLoading}
                  >
                    {isQueueLoading ? <Loader2 className="animate-spin" /> : <RefreshCw />}
                  </Button>
                </div>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                {!isAuthenticated ? (
                  <div className="rounded-[1.25rem] border border-border bg-muted p-4 text-sm font-semibold text-muted-foreground">
                    Connect your PDS to load scheduled posts.
                  </div>
                ) : null}
                {isAuthenticated && queue.length === 0 ? (
                  <div className="rounded-[1.25rem] border border-border bg-muted p-4 text-sm font-semibold text-muted-foreground">
                    Nothing queued yet. Write a post and schedule it.
                  </div>
                ) : null}
                {queue.map((item) => (
                  <button
                    key={item.rkey}
                    type="button"
                    className={cn(
                      "flex w-full flex-col gap-3 rounded-[1.25rem] border p-4 text-left transition",
                      selected?.rkey === item.rkey
                        ? "border-primary bg-muted"
                        : "border-border bg-card hover:bg-muted"
                    )}
                    onClick={() => setSelectedRkey(item.rkey)}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex flex-col gap-1">
                        <span className="line-clamp-2 text-sm font-black leading-5">
                          {item.record.posts[0]?.text || "Untitled post"}
                        </span>
                        <span className="text-xs font-semibold text-muted-foreground">
                          {formatSchedule(item.scheduledFor)}
                        </span>
                      </div>
                      <Badge variant={statusVariant(item.status)}>{item.status}</Badge>
                    </div>
                    {item.lastError ? (
                      <span className="rounded-xl bg-muted px-3 py-2 text-xs font-bold text-destructive">
                        {item.lastError}
                      </span>
                    ) : null}
                  </button>
                ))}
              </CardContent>
            </Card>

            {selected ? (
              <Card className="border-border bg-secondary">
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <Cloud />
                    Schedule record
                  </CardTitle>
                  <CardDescription>{selected.rkey}</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                  <div className="rounded-[1.25rem] bg-card/80 p-4">
                    <p className="text-sm font-semibold leading-6">
                      {selected.record.posts[0]?.text}
                    </p>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-xs font-bold text-muted-foreground">
                    <div className="rounded-2xl bg-card/70 p-3">
                      Collection
                      <span className="block text-foreground">at.skej.schedule</span>
                    </div>
                    <div className="rounded-2xl bg-card/70 p-3">
                      Attempts
                      <span className="block text-foreground">{selected.attempts}</span>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    <Button variant="outline" onClick={() => editSchedule(selected)}>
                      <Pencil data-icon="inline-start" />
                      Edit
                    </Button>
                    <Button variant="outline" onClick={() => retryPost(selected)}>
                      <RefreshCw data-icon="inline-start" />
                      Retry
                    </Button>
                    <Button variant="outline" onClick={() => deletePost(selected.rkey)}>
                      <Trash2 data-icon="inline-start" />
                      Delete
                    </Button>
                    <Button variant="sunny" onClick={() => publishSelected(selected)}>
                      <ArrowUpRight data-icon="inline-start" />
                      Publish
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : null}
          </aside>
        </section>
      </div>

      {scheduleOpen ? (
        <div
          aria-labelledby="schedule-sheet-title"
          aria-modal="true"
          className="fixed inset-0 z-20 bg-foreground/30 p-4 backdrop-blur-sm"
          role="dialog"
        >
          <div className="mx-auto mt-[12dvh] flex max-w-md flex-col gap-4 rounded-[2rem] border border-border bg-card p-5 shadow-[0_24px_80px_rgba(35,31,32,0.25)]">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-xl font-black" id="schedule-sheet-title">
                  Schedule
                </h2>
                <p className="text-sm font-semibold text-muted-foreground">
                  Pick when the worker should publish.
                </p>
              </div>
              <Button
                variant="ghost"
                size="icon"
                aria-label="Close schedule sheet"
                onClick={() => setScheduleOpen(false)}
              >
                <X />
              </Button>
            </div>
            <label className="flex flex-col gap-2">
              <span className="text-sm font-black">Date and time</span>
              <Input
                type="datetime-local"
                value={draft.scheduledFor}
                onChange={(event) =>
                  setDraft((current) => ({
                    ...current,
                    scheduledFor: event.target.value,
                  }))
                }
              />
            </label>
            <div className="rounded-2xl bg-secondary p-4 text-sm font-semibold text-secondary-foreground">
              The worker stores the scheduled job and draft record in SQLite for this
              alpha build.
            </div>
            <Button disabled={issues.length > 0 || firstPostCount === 0} onClick={scheduleDraft}>
              <CalendarClock data-icon="inline-start" />
              {editingRkey ? "Save update" : "Schedule post"}
            </Button>
          </div>
        </div>
      ) : null}
    </main>
  );
}
