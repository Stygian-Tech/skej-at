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
  LockKeyhole,
  MessageCircleReply,
  Plus,
  Quote,
  RefreshCw,
  Send,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import * as React from "react";

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
  ComposerDraft,
  MAX_POST_GRAPHEMES,
  countGraphemes,
  localDatetimeValue,
  validateComposerDraft,
} from "@/lib/editor";
import { cn } from "@/lib/utils";
import { ScheduledPostSummary, Viewer } from "@/lib/skejTypes";

const sampleViewer: Viewer = {
  did: "did:plc:skej-demo",
  handle: "sam.skej.at",
  displayName: "Sam",
};

const initialSchedule = new Date(Date.now() + 1000 * 60 * 60 * 3);

const sampleQueue: ScheduledPostSummary[] = [
  {
    rkey: "3l6sparkle",
    did: sampleViewer.did,
    scheduledFor: new Date(Date.now() + 1000 * 60 * 42).toISOString(),
    status: "scheduled",
    attempts: 0,
    record: {
      $type: "at.skej.schedule",
      scheduledFor: new Date(Date.now() + 1000 * 60 * 42).toISOString(),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      status: "scheduled",
      posts: [
        {
          text: "Testing a tiny PDS-powered queue. Scheduled posts belong to the user, not a mystery database.",
          langs: ["en"],
          tags: ["skej"],
        },
      ],
    },
  },
  {
    rkey: "3l6retryme",
    did: sampleViewer.did,
    scheduledFor: new Date(Date.now() - 1000 * 60 * 16).toISOString(),
    status: "failed",
    attempts: 2,
    lastError: "PDS rejected an image without alt text.",
    record: {
      $type: "at.skej.schedule",
      scheduledFor: new Date(Date.now() - 1000 * 60 * 16).toISOString(),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      status: "failed",
      posts: [
        {
          text: "Photo post for later.",
          embed: {
            images: [
              {
                id: "demo-image",
                alt: "",
                previewUrl: "/icon.png",
              },
            ],
          },
        },
      ],
    },
  },
];

function emptyDraft(): ComposerDraft {
  return {
    mode: "post",
    scheduledFor: localDatetimeValue(initialSchedule),
    posts: [
      {
        text: "",
        langs: ["en"],
        tags: [],
      },
    ],
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

function makeLocalSummary(draft: ComposerDraft): ScheduledPostSummary {
  const now = new Date();
  const record = {
    $type: "at.skej.schedule" as const,
    scheduledFor: new Date(draft.scheduledFor).toISOString(),
    createdAt: now.toISOString(),
    updatedAt: now.toISOString(),
    status: "scheduled" as const,
    posts: draft.posts.map((post) => ({
      ...post,
      text: post.text.trim(),
    })),
  };

  return {
    rkey: `3l6${Math.random().toString(36).slice(2, 9)}`,
    did: sampleViewer.did,
    scheduledFor: record.scheduledFor,
    status: "scheduled",
    attempts: 0,
    record,
  };
}

export function SkejApp() {
  const [viewer, setViewer] = React.useState<Viewer | null>(sampleViewer);
  const [draft, setDraft] = React.useState<ComposerDraft>(() => emptyDraft());
  const [queue, setQueue] = React.useState<ScheduledPostSummary[]>(sampleQueue);
  const [scheduleOpen, setScheduleOpen] = React.useState(false);
  const [handle, setHandle] = React.useState("sam.skej.at");
  const [selectedRkey, setSelectedRkey] = React.useState<string | null>(
    sampleQueue[0]?.rkey ?? null
  );

  const issues = React.useMemo(() => validateComposerDraft(draft), [draft]);
  const firstPostCount = countGraphemes(draft.posts[0]?.text ?? "");
  const selected = queue.find((item) => item.rkey === selectedRkey) ?? queue[0];

  function updatePost(index: number, text: string) {
    setDraft((current) => ({
      ...current,
      posts: current.posts.map((post, postIndex) =>
        postIndex === index ? { ...post, text } : post
      ),
    }));
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

  function scheduleDraft() {
    const validation = validateComposerDraft(draft);
    if (validation.length > 0) return;
    const item = makeLocalSummary(draft);
    setQueue((current) => [item, ...current]);
    setSelectedRkey(item.rkey);
    setDraft(emptyDraft());
    setScheduleOpen(false);
  }

  function retryPost(item: ScheduledPostSummary) {
    setQueue((current) =>
      current.map((entry) =>
        entry.rkey === item.rkey
          ? {
              ...entry,
              status: "scheduled",
              attempts: entry.attempts + 1,
              lastError: undefined,
              scheduledFor: new Date(Date.now() + 1000 * 60 * 15).toISOString(),
            }
          : entry
      )
    );
  }

  function deletePost(rkey: string) {
    setQueue((current) => current.filter((entry) => entry.rkey !== rkey));
    if (selectedRkey === rkey) {
      setSelectedRkey(queue.find((entry) => entry.rkey !== rkey)?.rkey ?? null);
    }
  }

  return (
    <main className="min-h-dvh overflow-hidden px-4 pb-28 pt-4 text-foreground sm:px-6 lg:px-8 lg:pb-4">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-5">
        <header className="flex items-center justify-between gap-3 rounded-[2rem] border border-white/80 bg-white/70 px-4 py-3 shadow-[0_20px_60px_rgba(70,52,70,0.1)] backdrop-blur">
          <div className="flex items-center gap-3">
            <div className="grid size-12 place-items-center rounded-2xl bg-primary text-xl font-black text-primary-foreground shadow-[0_14px_30px_rgba(255,79,109,0.22)]">
              S
            </div>
            <div className="flex flex-col">
              <span className="text-2xl font-black text-primary">Skej</span>
              <span className="text-xs font-bold text-muted-foreground">
                Schedule posts from your PDS
              </span>
            </div>
          </div>
          {viewer ? (
            <div className="flex items-center gap-2 rounded-full border border-border bg-card py-1 pl-1 pr-3">
              <div className="grid size-8 place-items-center rounded-full bg-secondary text-sm font-black text-secondary-foreground">
                {viewer.displayName?.charAt(0) ?? "S"}
              </div>
              <div className="hidden flex-col text-right sm:flex">
                <span className="text-xs font-black">{viewer.displayName}</span>
                <span className="text-xs text-muted-foreground">@{viewer.handle}</span>
              </div>
            </div>
          ) : (
            <Button size="sm" onClick={() => setViewer(sampleViewer)}>
              <LockKeyhole data-icon="inline-start" />
              Connect
            </Button>
          )}
        </header>

        <section className="grid gap-5 lg:grid-cols-[minmax(0,1.05fr)_minmax(360px,0.75fr)]">
          <div className="flex flex-col gap-5">
            {!viewer ? (
              <Card className="overflow-hidden">
                <CardHeader>
                  <CardTitle>Connect your PDS</CardTitle>
                  <CardDescription>
                    OAuth keeps publishing permission with your account.
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                  <div className="flex flex-col gap-2">
                    <label className="text-sm font-black" htmlFor="handle">
                      Handle
                    </label>
                    <Input
                      id="handle"
                      value={handle}
                      onChange={(event) => setHandle(event.target.value)}
                      placeholder="you.bsky.social"
                    />
                  </div>
                  <Button
                    onClick={() => {
                      window.location.href = `/oauth/start?handle=${encodeURIComponent(
                        handle
                      )}`;
                    }}
                  >
                    <Cloud data-icon="inline-start" />
                    OAuth to PDS
                  </Button>
                </CardContent>
              </Card>
            ) : null}

            <Card className="relative overflow-hidden">
              <div className="pointer-events-none absolute right-5 top-5 size-20 rounded-full bg-[#c8ff52]/60 blur-2xl" />
              <CardHeader className="relative">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <CardTitle className="text-2xl">Compose</CardTitle>
                    <CardDescription>
                      Build a post, thread, reply, or quote and send it later.
                    </CardDescription>
                  </div>
                  <Badge variant="sunny">Public PDS draft</Badge>
                </div>
              </CardHeader>
              <CardContent className="relative flex flex-col gap-4">
                <div className="rounded-[1.25rem] border border-[#ffd9e2] bg-[#fff2f5] p-3 sm:rounded-[1.5rem] sm:p-4">
                  <div className="flex gap-3">
                    <AlertCircle className="mt-0.5 size-5 shrink-0 text-primary sm:size-6" />
                    <p className="text-xs font-semibold leading-5 text-[#6f2937] sm:text-sm sm:leading-6">
                      Scheduled content is stored as a public AT Protocol record in
                      your PDS under <span className="font-black">at.skej.schedule</span>{" "}
                      until it publishes.
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
                        className="flex flex-col gap-2 rounded-[1.25rem] border border-border bg-white/80 p-2.5 sm:rounded-[1.5rem] sm:p-3"
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

                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                  <Button variant="outline" onClick={addThreadPost}>
                    <Plus data-icon="inline-start" />
                    Thread
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() =>
                      setDraft((current) => ({
                        ...current,
                        posts: current.posts.map((post, index) =>
                          index === 0
                            ? {
                                ...post,
                                embed: {
                                  ...post.embed,
                                  images: [
                                    {
                                      id: "draft-image",
                                      alt: "Colorful Skej preview art",
                                      previewUrl: "/icon.png",
                                    },
                                  ],
                                },
                              }
                            : post
                        ),
                      }))
                    }
                  >
                    <ImagePlus data-icon="inline-start" />
                    Images
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() =>
                      setDraft((current) => ({
                        ...current,
                        posts: current.posts.map((post, index) =>
                          index === 0
                            ? {
                                ...post,
                                embed: {
                                  ...post.embed,
                                  external: {
                                    uri: "https://skej.at",
                                    title: "Skej",
                                    description: "Schedule posts from your PDS.",
                                  },
                                },
                              }
                            : post
                        ),
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
                    Content warning
                  </Button>
                </div>

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
                            setDraft((current) => ({
                              ...current,
                              posts: current.posts.map((post, index) =>
                                index === 0
                                  ? {
                                      ...post,
                                      embed: {
                                        ...post.embed,
                                        images: post.embed?.images?.map((entry) =>
                                          entry.id === image.id
                                            ? { ...entry, alt: event.target.value }
                                            : entry
                                        ),
                                      },
                                    }
                                  : post
                              ),
                            }))
                          }
                        />
                      </label>
                    ))}
                  </div>
                ) : null}

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
                  <div className="flex items-end">
                    <Button
                      size="lg"
                      className="w-full sm:w-auto"
                      disabled={issues.length > 0}
                      onClick={scheduleDraft}
                    >
                      <CalendarClock data-icon="inline-start" />
                      Schedule
                    </Button>
                  </div>
                </div>

                {issues.length > 0 ? (
                  <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                    {issues[0]?.message}
                  </div>
                ) : (
                  <div className="flex items-center gap-2 rounded-2xl bg-[#e8fff3] px-4 py-3 text-sm font-black text-[#17613b]">
                    <CheckCircle2 />
                    Ready for {formatSchedule(new Date(draft.scheduledFor).toISOString())}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>

          <nav className="sticky bottom-[max(0.5rem,env(safe-area-inset-bottom))] z-10 rounded-full border border-white/80 bg-white/90 p-1.5 shadow-[0_18px_50px_rgba(70,52,70,0.18)] backdrop-blur lg:hidden">
            <div className="grid grid-cols-3 gap-2">
              <Button variant="default" size="sm">
                <Send data-icon="inline-start" />
                Compose
              </Button>
              <Button variant="secondary" size="sm" onClick={() => setScheduleOpen(true)}>
                <ListRestart data-icon="inline-start" />
                Queue
              </Button>
              <Button variant="outline" size="sm" onClick={() => setViewer(null)}>
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
                    <CardDescription>{queue.length} scheduled records</CardDescription>
                  </div>
                  <Button
                    variant="secondary"
                    size="icon"
                    aria-label="Open schedule sheet"
                    onClick={() => setScheduleOpen(true)}
                  >
                    <Clock3 />
                  </Button>
                </div>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                {queue.map((item) => (
                  <button
                    key={item.rkey}
                    type="button"
                    className={cn(
                      "flex w-full flex-col gap-3 rounded-[1.25rem] border p-4 text-left transition",
                      selected?.rkey === item.rkey
                        ? "border-primary bg-[#fff5f7]"
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
                      <span className="rounded-xl bg-[#ffe8eb] px-3 py-2 text-xs font-bold text-[#9c2034]">
                        {item.lastError}
                      </span>
                    ) : null}
                  </button>
                ))}
              </CardContent>
            </Card>

            {selected ? (
              <Card className="border-[#b8f6ff] bg-[#f1fdff]">
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <Cloud />
                    PDS record
                  </CardTitle>
                  <CardDescription>{selected.rkey}</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                  <div className="rounded-[1.25rem] bg-white/80 p-4">
                    <p className="text-sm font-semibold leading-6">
                      {selected.record.posts[0]?.text}
                    </p>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-xs font-bold text-muted-foreground">
                    <div className="rounded-2xl bg-white/70 p-3">
                      Collection
                      <span className="block text-foreground">at.skej.schedule</span>
                    </div>
                    <div className="rounded-2xl bg-white/70 p-3">
                      Attempts
                      <span className="block text-foreground">{selected.attempts}</span>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    <Button variant="outline" onClick={() => retryPost(selected)}>
                      <RefreshCw data-icon="inline-start" />
                      Retry
                    </Button>
                    <Button variant="outline" onClick={() => deletePost(selected.rkey)}>
                      <Trash2 data-icon="inline-start" />
                      Delete
                    </Button>
                  </div>
                  <Button variant="sunny">
                    <ArrowUpRight data-icon="inline-start" />
                    Publish now
                  </Button>
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
          className="fixed inset-0 z-20 bg-[#231f20]/30 p-4 backdrop-blur-sm"
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
              The worker stores only the due time and rkey in SQLite; post content stays
              in your PDS record.
            </div>
            <Button disabled={issues.length > 0 || firstPostCount === 0} onClick={scheduleDraft}>
              <CalendarClock data-icon="inline-start" />
              Schedule post
            </Button>
          </div>
        </div>
      ) : null}
    </main>
  );
}
