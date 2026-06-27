"use client";

import {
  AlertCircle,
  ArrowUpRight,
  CalendarClock,
  CheckCircle2,
  ChevronDown,
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
import { SkejLogoMark } from "@/components/SkejLogoMark";
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
  cancelSchedule,
  duplicateSchedule,
  getViewer,
  listAccountSchedules,
  listAccounts,
  listSchedules,
  logout,
  publishNow,
  recordScheduleView,
  retrySchedule,
  updateSchedule,
} from "@/lib/api";
import {
  ComposerDraft,
  MAX_POST_GRAPHEMES,
  MAX_SCHEDULE_TITLE_GRAPHEMES,
  countGraphemes,
  localDatetimeValue,
  validateComposerDraft,
} from "@/lib/editor";
import { cn } from "@/lib/utils";
import {
  CommunityCalendarEventRecord,
  ManagedAccount,
  PostPlan,
  ScheduledPostSummary,
  Viewer,
} from "@/lib/skejTypes";

type AuthStatus = "loading" | "anonymous" | "authenticated";
type QueueMode = "upcoming" | "history";

const friendlyErrorReplacements: Array<[RegExp, string]> = [
  [/\bOAuth\b/gi, "sign-in"],
  [/\bPDS\b/g, "Bluesky account"],
  [/\bSQLite\b/gi, "Skej"],
  [/\bAPI\b/g, "service"],
  [/\bendpoint\b/gi, "service"],
  [/\btoken\b/gi, "session"],
  [/\bat\.skej\.schedule\b/g, "scheduled post"],
  [/\bapp\.bsky\.feed\.post\b/g, "Bluesky post"],
  [/\brecord\b/gi, "post"],
  [/\bworker\b/gi, "scheduler"],
];

function defaultScheduleDate(minutes = 180) {
  return new Date(Date.now() + minutes * 60_000);
}

function emptyDraft(date = defaultScheduleDate()): ComposerDraft {
  return {
    mode: "post",
    title: "",
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
    title: "",
    scheduledFor: "",
    posts: [{ text: "", langs: ["en"], tags: [] }],
  };
}

function draftFromSchedule(
  item: ScheduledPostSummary,
  date = new Date(item.scheduledAt)
): ComposerDraft {
  const first = item.record.posts[0];
  return {
    mode: first?.reply ? "reply" : first?.embed?.record ? "quote" : "post",
    title: item.record.title ?? "",
    scheduledFor: localDatetimeValue(date),
    timezone: item.record.userTimezone,
    dependencyScheduleUri: item.record.dependency?.dependsOnScheduleUri,
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
    case "canceled":
    case "draft":
    case "blocked":
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

function friendlyErrorMessage(message: string) {
  return friendlyErrorReplacements.reduce(
    (copy, [pattern, replacement]) => copy.replace(pattern, replacement),
    message
  );
}

function scheduleErrorMessage(item: ScheduledPostSummary) {
  return item.lastError?.message ?? item.record.lastError?.message;
}

function statusLabel(status: string) {
  return status
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function scheduleTitle(item: ScheduledPostSummary) {
  return item.record.title?.trim() || item.record.posts[0]?.text?.trim() || "Untitled post";
}

function calendarDayKey(value: string) {
  return new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(value));
}

function calendarDayLabel(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
  }).format(new Date(value));
}

function calendarMonthLabel(value: Date) {
  return new Intl.DateTimeFormat(undefined, {
    month: "long",
    year: "numeric",
  }).format(value);
}

function buildCalendarGridDays(monthDate: Date) {
  const year = monthDate.getFullYear();
  const month = monthDate.getMonth();
  const first = new Date(year, month, 1);
  const start = new Date(first);
  start.setDate(first.getDate() - first.getDay());
  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    return {
      date,
      key: calendarDayKey(date.toISOString()),
      inMonth: date.getMonth() === month,
    };
  });
}

function buildCalendarEvent(item: ScheduledPostSummary): CommunityCalendarEventRecord {
  const startsAt = item.scheduledAt;
  const endsAt = new Date(new Date(startsAt).getTime() + 30 * 60_000).toISOString();
  return {
    $type: "community.lexicon.calendar.event",
    name: scheduleTitle(item),
    description: item.record.posts.map((post) => post.text).filter(Boolean).join("\n\n"),
    startsAt,
    endsAt,
    timezone: item.record.userTimezone,
    status: item.status,
    source: {
      $type: "at.skej.schedule",
      uri: item.scheduleUri,
      did: item.did,
      rkey: item.rkey,
    },
    content: {
      recordType: item.record.recordType,
      publishRkey: item.record.publishRkey,
      publishedUri: item.publishedUri ?? item.record.publishedUri,
    },
  };
}

function upsertQueueItem(
  queue: ScheduledPostSummary[],
  item: ScheduledPostSummary
): ScheduledPostSummary[] {
  const exists = queue.some((entry) => entry.rkey === item.rkey);
  if (!exists) return sortScheduleItems([...queue, item]);
  return sortScheduleItems(queue.map((entry) => (entry.rkey === item.rkey ? item : entry)));
}

function sortScheduleItems(items: ScheduledPostSummary[]) {
  return [...items].sort((left, right) => {
    const byTime =
      new Date(left.scheduledAt).getTime() - new Date(right.scheduledAt).getTime();
    if (byTime !== 0) return byTime;
    return left.rkey.localeCompare(right.rkey);
  });
}

function isHistoricalSchedule(item: ScheduledPostSummary, now = new Date()) {
  return (
    new Date(item.scheduledAt).getTime() < now.getTime() ||
    ["published", "failed", "canceled"].includes(item.status)
  );
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

function ViewerAvatar({ viewer }: { viewer: Viewer | null }) {
  if (viewer?.avatar) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        alt=""
        className="size-10 rounded-full border border-border object-cover"
        referrerPolicy="no-referrer"
        src={viewer.avatar}
      />
    );
  }

  return (
    <div className="grid size-10 place-items-center rounded-full bg-secondary text-base font-black text-secondary-foreground">
      {firstInitial(viewer)}
    </div>
  );
}

export function SkejApp() {
  const [authStatus, setAuthStatus] = React.useState<AuthStatus>("loading");
  const [viewer, setViewer] = React.useState<Viewer | null>(null);
  const [accounts, setAccounts] = React.useState<ManagedAccount[]>([]);
  const [selectedAccountDid, setSelectedAccountDid] = React.useState<string | null>(null);
  const [draft, setDraft] = React.useState<ComposerDraft>(() => hydrationSafeDraft());
  const [queue, setQueue] = React.useState<ScheduledPostSummary[]>([]);
  const [queueMode, setQueueMode] = React.useState<QueueMode>("upcoming");
  const [viewedHistoryAuditKeys, setViewedHistoryAuditKeys] = React.useState<Set<string>>(
    () => new Set()
  );
  const [scheduleOpen, setScheduleOpen] = React.useState(false);
  const [calendarOpen, setCalendarOpen] = React.useState(false);
  const [selectedCalendarDay, setSelectedCalendarDay] = React.useState<string | null>(null);
  const [expandedCalendarEventUri, setExpandedCalendarEventUri] = React.useState<string | null>(null);
  const [selectedRkey, setSelectedRkey] = React.useState<string | null>(null);
  const [editingRkey, setEditingRkey] = React.useState<string | null>(null);
  const [isQueueLoading, setIsQueueLoading] = React.useState(false);
  const [isMutating, setIsMutating] = React.useState(false);
  const [actionError, setActionError] = React.useState<string | null>(null);
  const [actionMessage, setActionMessage] = React.useState<string | null>(null);
  const [profileOpen, setProfileOpen] = React.useState(false);

  const issues = React.useMemo(() => validateComposerDraft(draft), [draft]);
  const firstPostCount = countGraphemes(draft.posts[0]?.text ?? "");
  const titleCount = countGraphemes(draft.title ?? "");
  const sortedQueue = React.useMemo(() => sortScheduleItems(queue), [queue]);
  const upcomingQueue = React.useMemo(
    () => sortedQueue.filter((item) => !isHistoricalSchedule(item)),
    [sortedQueue]
  );
  const historyQueue = React.useMemo(
    () => [...sortedQueue].filter((item) => isHistoricalSchedule(item)).reverse(),
    [sortedQueue]
  );
  const visibleQueue = queueMode === "history" ? historyQueue : upcomingQueue;
  const selected =
    sortedQueue.find((item) => item.rkey === selectedRkey) ?? visibleQueue[0] ?? sortedQueue[0] ?? null;
  const isAuthenticated = authStatus === "authenticated" && viewer !== null;
  const selectedAccount =
    accounts.find((account) => account.did === selectedAccountDid) ?? accounts[0] ?? null;
  const canCreateForSelectedBrand = true;
  const canApproveSelectedBrand = true;
  const managedParents = sortedQueue.filter((item) =>
    ["scheduled", "blocked", "publishing", "published"].includes(item.status)
  );
  const statusGroups = React.useMemo(
    () =>
      [
        "draft",
        "scheduled",
        "blocked",
        "publishing",
        "failed",
        "published",
        "canceled",
        "total",
      ].map((status) => ({
        status,
        count:
          status === "total"
            ? sortedQueue.length
            : sortedQueue.filter((item) => item.status === status).length,
      })),
    [sortedQueue]
  );
  const calendarDays = React.useMemo(() => {
    const counts = new Map<string, number>();
    for (const item of sortedQueue) {
      const day = calendarDayLabel(item.scheduledAt);
      counts.set(day, (counts.get(day) ?? 0) + 1);
    }
    return Array.from(counts.entries()).slice(0, 7);
  }, [sortedQueue]);
  const calendarEvents = React.useMemo(
    () =>
      sortedQueue
        .map(buildCalendarEvent)
        .sort((a, b) => a.startsAt.localeCompare(b.startsAt)),
    [sortedQueue]
  );
  const calendarEventsByDay = React.useMemo(() => {
    const grouped = new Map<string, CommunityCalendarEventRecord[]>();
    for (const event of calendarEvents) {
      const day = calendarDayKey(event.startsAt);
      grouped.set(day, [...(grouped.get(day) ?? []), event]);
    }
    return grouped;
  }, [calendarEvents]);
  const visibleMonth = React.useMemo(() => {
    if (calendarEvents[0]) return new Date(calendarEvents[0].startsAt);
    return new Date();
  }, [calendarEvents]);
  const calendarMonths = React.useMemo(() => {
    const start = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1);
    return Array.from({ length: 18 }, (_, index) => {
      const monthDate = new Date(start);
      monthDate.setMonth(start.getMonth() + index);
      return {
        key: `${monthDate.getFullYear()}-${monthDate.getMonth()}`,
        date: monthDate,
        days: buildCalendarGridDays(monthDate),
      };
    });
  }, [visibleMonth]);
  const selectedCalendarEvents = React.useMemo(() => {
    const day = selectedCalendarDay ?? calendarDayKey(visibleMonth.toISOString());
    return calendarEventsByDay.get(day) ?? [];
  }, [calendarEventsByDay, selectedCalendarDay, visibleMonth]);

  const refreshSchedules = React.useCallback(async () => {
    setIsQueueLoading(true);
    try {
      const records = selectedAccountDid
        ? await listAccountSchedules(selectedAccountDid)
        : await listSchedules();
      const sortedRecords = sortScheduleItems(records);
      setQueue(sortedRecords);
      setSelectedRkey((current) =>
        current && sortedRecords.some((record) => record.rkey === current)
          ? current
          : sortedRecords[0]?.rkey ?? null
      );
    } finally {
      setIsQueueLoading(false);
    }
  }, [selectedAccountDid]);

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
        const loadedAccounts = await listAccounts();
        if (cancelled) return;
        setAccounts(loadedAccounts);
        const defaultDid =
          currentViewer.defaultAccountDid ??
          loadedAccounts.find((account) => account.isDefault)?.did ??
          loadedAccounts[0]?.did ??
          currentViewer.did;
        setSelectedAccountDid(defaultDid);
        const records = defaultDid
          ? await listAccountSchedules(defaultDid)
          : await listSchedules();
        const sortedRecords = sortScheduleItems(records);
        if (cancelled) return;
        setQueue(sortedRecords);
        setSelectedRkey(sortedRecords[0]?.rkey ?? null);
      } catch (error) {
        if (cancelled) return;
        setViewer(null);
        setAccounts([]);
        setSelectedAccountDid(null);
        setQueue([]);
        setSelectedRkey(null);
        setAuthStatus("anonymous");
        if (error instanceof Error && !error.message.toLowerCase().includes("sign in")) {
          setActionError(friendlyErrorMessage(error.message));
        }
      }
    }

    void loadSession();
    return () => {
      cancelled = true;
      window.clearTimeout(draftTimer);
    };
  }, []);

  React.useEffect(() => {
    if (!calendarOpen) return;
    const previousBodyOverflow = document.body.style.overflow;
    const previousDocumentOverflow = document.documentElement.style.overflow;
    document.body.style.overflow = "hidden";
    document.documentElement.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousBodyOverflow;
      document.documentElement.style.overflow = previousDocumentOverflow;
    };
  }, [calendarOpen]);

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
      const nextStatus = canApproveSelectedBrand ? "scheduled" : "draft";
      const item = editingRkey
        ? await updateSchedule(editingRkey, draft, selectedAccountDid ?? undefined, nextStatus)
        : await createSchedule(draft, selectedAccountDid ?? undefined, nextStatus);
      setQueue((current) => upsertQueueItem(current, item));
      setSelectedRkey(item.rkey);
      setActionMessage(
        nextStatus === "draft"
          ? "Draft proposed for approval."
          : editingRkey
            ? "Schedule updated."
            : "Post scheduled."
      );
      resetComposer();
      setScheduleOpen(false);
    } catch (error) {
      setActionError(
        error instanceof Error
          ? friendlyErrorMessage(error.message)
          : "Could not schedule post."
      );
    } finally {
      setIsMutating(false);
    }
  }

  async function retryPost(item: ScheduledPostSummary) {
    setIsMutating(true);
    setActionError(null);
    try {
      const updated = await retrySchedule(item.did, item.rkey);
      setQueue((current) => upsertQueueItem(current, updated));
      setSelectedRkey(updated.rkey);
      setActionMessage("Retry requested.");
    } catch (error) {
      setActionError(
        error instanceof Error ? friendlyErrorMessage(error.message) : "Could not retry post."
      );
    } finally {
      setIsMutating(false);
    }
  }

  async function deletePost(item: ScheduledPostSummary) {
    setIsMutating(true);
    setActionError(null);
    try {
      const updated = await cancelSchedule(item.did, item.rkey);
      setQueue((current) => upsertQueueItem(current, updated));
      setSelectedRkey(updated.rkey);
      if (editingRkey === item.rkey) resetComposer();
      setActionMessage("Schedule canceled.");
    } catch (error) {
      setActionError(
        error instanceof Error
          ? friendlyErrorMessage(error.message)
          : "Could not delete schedule."
      );
    } finally {
      setIsMutating(false);
    }
  }

  async function publishSelected(item: ScheduledPostSummary) {
    setIsMutating(true);
    setActionError(null);
    try {
      const published = await publishNow(item.rkey, item.did);
      setQueue((current) => upsertQueueItem(current, published));
      setSelectedRkey(published.rkey);
      setActionMessage("Post published.");
    } catch (error) {
      setActionError(
        error instanceof Error
          ? friendlyErrorMessage(error.message)
          : "Could not publish post."
      );
    } finally {
      setIsMutating(false);
    }
  }

  async function duplicatePost(item: ScheduledPostSummary) {
    setIsMutating(true);
    setActionError(null);
    try {
      const duplicated = await duplicateSchedule(item.did, item.rkey);
      setQueue((current) => upsertQueueItem(current, duplicated));
      setSelectedRkey(duplicated.rkey);
      setActionMessage("Schedule duplicated as a draft.");
    } catch (error) {
      setActionError(
        error instanceof Error
          ? friendlyErrorMessage(error.message)
          : "Could not duplicate schedule."
      );
    } finally {
      setIsMutating(false);
    }
  }

  async function switchAccount(did: string) {
    setSelectedAccountDid(did);
    setSelectedRkey(null);
    setQueueMode("upcoming");
    setQueue([]);
    setIsQueueLoading(true);
    try {
      const records = await listAccountSchedules(did);
      const sortedRecords = sortScheduleItems(records);
      setQueue(sortedRecords);
      setSelectedRkey(sortedRecords[0]?.rkey ?? null);
    } finally {
      setIsQueueLoading(false);
    }
  }

  async function selectSchedule(item: ScheduledPostSummary) {
    setSelectedRkey(item.rkey);
    if (!selectedAccountDid || !isHistoricalSchedule(item)) return;
    const auditKey = `${selectedAccountDid}:${item.rkey}`;
    if (viewedHistoryAuditKeys.has(auditKey)) return;
    setViewedHistoryAuditKeys((current) => new Set(current).add(auditKey));
    try {
      await recordScheduleView(selectedAccountDid, item.rkey);
    } catch {
      setViewedHistoryAuditKeys((current) => {
        const next = new Set(current);
        next.delete(auditKey);
        return next;
      });
    }
  }

  async function signOut() {
    setIsMutating(true);
    try {
      await logout();
      setViewer(null);
      setAccounts([]);
      setSelectedAccountDid(null);
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
    <main className="min-h-dvh overflow-hidden px-4 pb-28 pt-[1.125rem] text-foreground sm:px-6 lg:px-8 lg:pb-4">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-[1.125rem]">
        <header className="sticky top-0 z-40 flex items-center justify-between gap-3 rounded-[2rem] border border-border bg-card/95 px-4 py-3 shadow-[0_14px_38px_rgba(35,31,32,0.08)] backdrop-blur">
            <Link className="flex min-w-0 items-center gap-3" href="/">
              <SkejLogoMark />
              <div className="flex min-w-0 flex-col">
                <div className="flex items-center gap-2">
                  <span className="text-2xl font-black text-primary">Skej</span>
                  <Badge variant="sunny">Alpha</Badge>
                </div>
                <span className="truncate text-xs font-bold text-muted-foreground">
                  Schedule ATmosphere posts
                </span>
              </div>
            </Link>
            <div className="flex items-center gap-2">
              <ThemeToggle />
              {isAuthenticated ? (
                <div className="relative">
                  <div className="flex h-12 items-center gap-1 rounded-full border border-border bg-card p-1">
                    <button
                      type="button"
                      className="grid size-10 shrink-0 place-items-center rounded-full p-0 text-left transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      aria-expanded={profileOpen}
                      onClick={() => setProfileOpen((current) => !current)}
                    >
                      <ViewerAvatar viewer={viewer} />
                    </button>
                    <div className="relative block">
                      <select
                        aria-label="Connected Account"
                        className="skej-select-control h-10 w-28 rounded-full border border-border bg-background/80 py-0 pl-4 pr-10 text-sm font-black leading-none outline-none transition hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring sm:w-44"
                        value={selectedAccountDid ?? ""}
                        onChange={(event) => void switchAccount(event.target.value)}
                      >
                        {accounts.map((account) => (
                          <option key={account.did} value={account.did}>
                            {account.handle ?? account.did}
                          </option>
                        ))}
                      </select>
                      <ChevronDown
                        aria-hidden="true"
                        className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                      />
                    </div>
                    <Button
                      aria-label="Log Out"
                      className="size-10 rounded-full border border-border bg-background/80 p-0"
                      disabled={isMutating}
                      onClick={signOut}
                      size="icon"
                      variant="ghost"
                    >
                      <LogOut />
                    </Button>
                  </div>
                  {profileOpen ? (
                    <div className="absolute right-0 top-[calc(100%+0.5rem)] z-30 max-h-[calc(100dvh-6rem)] w-[min(24rem,calc(100vw-2rem))] overflow-auto rounded-[1.5rem] border border-border bg-card p-4 shadow-[0_16px_48px_rgba(35,31,32,0.18)]">
                      <div className="mb-3">
                        <div className="text-sm font-black">Profile</div>
                        <div className="truncate text-xs font-semibold text-muted-foreground">
                          {viewer.handle ?? viewer.did}
                        </div>
                      </div>
                      <Link
                        className="mb-4 flex items-center justify-between gap-3 rounded-2xl border border-border bg-background/60 px-3 py-3 text-sm font-black transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        href="/app/account"
                        onClick={() => setProfileOpen(false)}
                      >
                        <span>Admin Panel</span>
                        <ArrowUpRight className="size-4" />
                      </Link>
                    </div>
                  ) : null}
                </div>
              ) : (
                <Button
                  size="sm"
                  onClick={() => {
                    document
                      .getElementById("connect-account")
                      ?.scrollIntoView({ behavior: "smooth", block: "start" });
                  }}
                >
                  <LockKeyhole data-icon="inline-start" />
                  Connect
                </Button>
              )}
            </div>
        </header>

        <div className="sticky top-[5.75rem] z-30 flex items-center gap-2 rounded-[1.25rem] border border-accent/70 bg-accent px-3 py-2 text-xs font-black text-accent-foreground shadow-[0_10px_28px_rgba(216,188,83,0.18)]">
          <span>Work in progress. Keep a copy of mission-critical content.</span>
        </div>

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
              <Card className="overflow-hidden" id="connect-account">
                <CardHeader>
                  <CardTitle>Connect Bluesky</CardTitle>
                  <CardDescription>
                    Enter your Bluesky handle so Skej can show your scheduled posts
                    and create new ones for that account.
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                  <OAuthLoginForm compact />
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
                        Build a post, reply, or quote and send it later.
                      </CardDescription>
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="relative flex flex-col gap-4">
                  <div className="rounded-[1.25rem] border border-border bg-muted p-3 sm:rounded-[1.5rem] sm:p-4">
                    <div className="flex gap-3">
                      <AlertCircle className="mt-0.5 shrink-0 text-primary" />
                      <p className="text-xs font-semibold leading-5 text-muted-foreground sm:text-sm sm:leading-6">
                        Skej posts are not private. Keep a copy of anything sensitive
                        somewhere else.
                      </p>
                    </div>
                  </div>

                  <label className="flex flex-col gap-2">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-black">Title</span>
                      <span
                        className={cn(
                          "text-xs font-black",
                          titleCount > MAX_SCHEDULE_TITLE_GRAPHEMES
                            ? "text-destructive"
                            : "text-muted-foreground"
                        )}
                      >
                        {titleCount}/{MAX_SCHEDULE_TITLE_GRAPHEMES}
                      </span>
                    </div>
                    <Input
                      value={draft.title ?? ""}
                      onChange={(event) =>
                        setDraft((current) => ({
                          ...current,
                          title: event.target.value,
                        }))
                      }
                      placeholder="Launch reminder, promo post, follow-up..."
                      aria-label="Schedule title"
                    />
                  </label>

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
                              ? "border-primary bg-primary text-primary-foreground shadow-[0_8px_18px_rgba(255,79,109,0.12)]"
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

                  {draft.mode === "reply" || draft.mode === "quote" ? (
                    <label className="flex flex-col gap-2 rounded-[1.25rem] border border-border bg-card p-3">
                      <span className="text-sm font-black">
                        {draft.mode === "reply" ? "Reply to" : "Quote"}
                      </span>
                      <div className="relative rounded-2xl border border-border bg-background shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition focus-within:ring-2 focus-within:ring-ring">
                        <select
                          className="skej-select-control min-h-11 w-full rounded-2xl px-3 pr-10 text-sm font-semibold outline-none"
                          value={draft.dependencyScheduleUri ?? ""}
                          onChange={(event) =>
                            setDraft((current) => ({
                              ...current,
                              dependencyScheduleUri: event.target.value || undefined,
                            }))
                          }
                        >
                          <option value="">Choose a Skej-managed post</option>
                          {managedParents.map((item) => (
                            <option key={item.scheduleUri} value={item.scheduleUri}>
                              {scheduleTitle(item)}
                            </option>
                          ))}
                        </select>
                        <ChevronDown
                          aria-hidden="true"
                          className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                        />
                      </div>
                    </label>
                  ) : null}

                  <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
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
                              description: "Plan Bluesky posts ahead with Skej.",
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
                      <div className="relative rounded-2xl border border-input bg-card shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition focus-within:ring-2 focus-within:ring-ring">
                        <Input
                          className="skej-date-control border-0 bg-transparent pr-12 focus-visible:ring-0"
                          type="datetime-local"
                          value={draft.scheduledFor}
                          onChange={(event) =>
                            setDraft((current) => ({
                              ...current,
                              scheduledFor: event.target.value,
                            }))
                          }
                        />
                        <CalendarClock
                          aria-hidden="true"
                          className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                        />
                      </div>
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
                        disabled={issues.length > 0 || isMutating || !canCreateForSelectedBrand}
                        onClick={scheduleDraft}
                      >
                        {isMutating ? (
                          <Loader2 className="animate-spin" data-icon="inline-start" />
                        ) : (
                          <CalendarClock data-icon="inline-start" />
                        )}
                        {editingRkey
                          ? "Save update"
                          : canApproveSelectedBrand
                            ? "Schedule"
                            : "Propose"}
                      </Button>
                    </div>
                  </div>

                  {issues.length > 0 ? (
                    <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                      {issues[0]?.message}
                    </div>
                  ) : !canCreateForSelectedBrand ? (
                    <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                      You can view this brand, but you need create permission to propose posts.
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

          <nav className="sticky bottom-[max(0.5rem,env(safe-area-inset-bottom))] z-10 rounded-full border border-border bg-card/95 p-1.5 shadow-[0_12px_30px_rgba(35,31,32,0.12)] backdrop-blur lg:hidden">
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
                Scheduled
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={isAuthenticated ? signOut : undefined}
              >
                <LockKeyhole data-icon="inline-start" />
                Account
              </Button>
            </div>
          </nav>

          <aside className="flex flex-col gap-5">
            <Card className="overflow-hidden">
              <CardHeader>
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <CardTitle>Content Queue</CardTitle>
                    <CardDescription>
                      {isQueueLoading
                        ? "Refreshing..."
                        : `${visibleQueue.length} ${queueMode === "history" ? "Historical Posts" : "Upcoming Posts"}`}
                    </CardDescription>
                  </div>
                  <div className="flex items-center gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setCalendarOpen(true)}
                      disabled={!isAuthenticated}
                    >
                      <ArrowUpRight data-icon="inline-start" />
                      Calendar
                    </Button>
                    <Button
                      variant="secondary"
                      size="icon"
                      aria-label="Refresh Scheduled Posts"
                      onClick={refreshSchedules}
                      disabled={!isAuthenticated || isQueueLoading}
                    >
                      {isQueueLoading ? <Loader2 className="animate-spin" /> : <RefreshCw />}
                    </Button>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                {calendarDays.length > 0 ? (
                  <div className="flex gap-2 overflow-x-auto pb-1">
                    {calendarDays.map(([day, count]) => (
                      <button
                        type="button"
                        className="flex min-w-24 items-center justify-between gap-3 rounded-full bg-muted px-3 py-2 text-left text-xs font-bold transition hover:bg-secondary"
                        key={day}
                        onClick={() => {
                          const match = calendarEvents.find(
                            (event) => calendarDayLabel(event.startsAt) === day
                          );
                          setSelectedCalendarDay(
                            match ? calendarDayKey(match.startsAt) : selectedCalendarDay
                          );
                          setExpandedCalendarEventUri(null);
                          setCalendarOpen(true);
                        }}
                      >
                        <span>{day}</span>
                        <span>{count}</span>
                      </button>
                    ))}
                  </div>
                ) : (
                  <div className="rounded-xl bg-muted px-3 py-2 text-sm font-semibold text-muted-foreground">
                    No scheduled days yet.
                  </div>
                )}
                <div className="grid grid-cols-2 gap-2 rounded-full bg-muted p-1">
                  {[
                    { mode: "upcoming" as const, label: `Upcoming ${upcomingQueue.length}` },
                    { mode: "history" as const, label: `History ${historyQueue.length}` },
                  ].map((item) => (
                    <button
                      type="button"
                      className={cn(
                        "min-h-9 rounded-full px-3 text-sm font-black transition",
                        queueMode === item.mode
                          ? "bg-card text-foreground shadow-[0_6px_16px_rgba(35,31,32,0.08)]"
                          : "text-muted-foreground hover:text-foreground"
                      )}
                      key={item.mode}
                      onClick={() => {
                        setQueueMode(item.mode);
                        const nextQueue = item.mode === "history" ? historyQueue : upcomingQueue;
                        if (nextQueue[0]) {
                          void selectSchedule(nextQueue[0]);
                        } else {
                          setSelectedRkey(null);
                        }
                      }}
                    >
                      {item.label}
                    </button>
                  ))}
                </div>
                {!isAuthenticated ? (
                  <div className="rounded-[1.25rem] border border-border bg-muted p-4 text-sm font-semibold text-muted-foreground">
                    Connect Bluesky to load scheduled posts.
                  </div>
                ) : null}
                {isAuthenticated && visibleQueue.length === 0 ? (
                  <div className="rounded-[1.25rem] border border-border bg-muted p-4 text-sm font-semibold text-muted-foreground">
                    {queueMode === "history"
                      ? "No historical posts yet."
                      : "Nothing scheduled yet. Write a post and choose a time."}
                  </div>
                ) : null}
                {visibleQueue.map((item) => (
                  <button
                    key={item.rkey}
                    type="button"
                    className={cn(
                      "flex w-full flex-col gap-2 rounded-[1.25rem] border px-4 py-3 text-left transition",
                      selected?.rkey === item.rkey
                        ? "border-primary bg-muted"
                        : "border-border bg-card hover:bg-muted"
                    )}
                    onClick={() => void selectSchedule(item)}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex flex-col gap-1">
                        <span className="line-clamp-2 text-sm font-black leading-5">
                          {scheduleTitle(item)}
                        </span>
                        <span className="text-xs font-semibold text-muted-foreground">
                          {formatSchedule(item.scheduledAt)}
                        </span>
                      </div>
                      <Badge variant={statusVariant(item.status)}>
                        {statusLabel(item.status)}
                      </Badge>
                    </div>
                    {scheduleErrorMessage(item) ? (
                      <span className="rounded-xl bg-muted px-3 py-2 text-xs font-bold text-destructive">
                        {friendlyErrorMessage(scheduleErrorMessage(item) ?? "")}
                      </span>
                    ) : null}
                  </button>
                ))}

                {selected ? (
                  <div
                    className="mt-1 flex flex-col gap-3 rounded-[1.25rem] border border-border bg-secondary p-4"
                    id="schedule-details"
                  >
                    <div>
                      <div className="flex items-center gap-2 text-lg font-black">
                        <CalendarClock />
                        {scheduleTitle(selected)}
                      </div>
                      <div className="text-sm font-semibold text-muted-foreground">
                        Scheduled for {formatSchedule(selected.scheduledAt)}
                      </div>
                    </div>
                    <div className="rounded-[1.25rem] bg-card/80 p-3">
                      {selected.record.title ? (
                        <div className="mb-2 text-xs font-black text-muted-foreground">
                          Post Content
                        </div>
                      ) : null}
                      <p className="line-clamp-3 text-sm font-semibold leading-6">
                        {selected.record.posts[0]?.text}
                      </p>
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-xs font-bold text-muted-foreground">
                      <div className="rounded-2xl bg-card/70 p-3">
                        Status
                        <span className="block text-foreground">
                          {statusLabel(selected.status)}
                        </span>
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
                      <Button variant="outline" onClick={() => duplicatePost(selected)}>
                        <Plus data-icon="inline-start" />
                        Duplicate
                      </Button>
                      <Button variant="outline" onClick={() => deletePost(selected)}>
                        <Trash2 data-icon="inline-start" />
                        Cancel
                      </Button>
                      <Button
                        className="col-span-2"
                        variant="sunny"
                        onClick={() => publishSelected(selected)}
                      >
                        <ArrowUpRight data-icon="inline-start" />
                        Publish
                      </Button>
                    </div>
                    <details className="rounded-2xl bg-card/70 p-3 text-xs font-semibold text-muted-foreground">
                      <summary className="cursor-pointer font-black text-foreground">
                        Advanced
                      </summary>
                      <div className="mt-2 grid gap-1 break-all">
                        <span>Schedule: {selected.scheduleUri}</span>
                        <span>Published: {selected.publishedUri ?? "Not published"}</span>
                      </div>
                    </details>
                  </div>
                ) : null}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Status</CardTitle>
                <CardDescription>Where each post stands right now.</CardDescription>
              </CardHeader>
              <CardContent className="grid grid-cols-2 gap-2">
                {statusGroups.map((group) => (
                  <div className="rounded-xl bg-muted px-3 py-2" key={group.status}>
                    <div className="text-xs font-bold text-muted-foreground">
                      {statusLabel(group.status)}
                    </div>
                    <div className="text-lg font-black">{group.count}</div>
                  </div>
                ))}
              </CardContent>
            </Card>
          </aside>
        </section>
      </div>

      {calendarOpen ? (
        <div
          aria-labelledby="content-calendar-title"
          aria-modal="true"
          className="fixed inset-0 z-[100] overflow-hidden bg-foreground/30 p-4 backdrop-blur-sm"
          onClick={() => setCalendarOpen(false)}
          role="dialog"
        >
          <div
            className="mx-auto flex h-[calc(100dvh-2rem)] max-w-6xl flex-col gap-4 rounded-[2rem] border border-border bg-card p-4 shadow-[0_16px_48px_rgba(35,31,32,0.18)] sm:p-5"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <div className="flex items-center gap-2">
                  <CalendarClock />
                  <h2 className="text-2xl font-black" id="content-calendar-title">
                    Content Calendar
                  </h2>
                </div>
                <p className="mt-1 text-sm font-semibold text-muted-foreground">
                  {selectedAccount?.handle ?? selectedAccount?.displayName ?? "Selected account"}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant="sunny">
                  community.lexicon.calendar.event
                </Badge>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Close Content Calendar"
                  onClick={() => setCalendarOpen(false)}
                >
                  <X />
                </Button>
              </div>
            </div>

            <div className="grid min-h-0 flex-1 gap-4 lg:grid-cols-[minmax(0,1.45fr)_minmax(320px,0.75fr)]">
              <section className="flex min-h-0 flex-col rounded-[1.5rem] border border-border bg-background/50 p-3 sm:p-4">
                <div className="mb-3 flex shrink-0 items-center justify-between gap-3">
                  <div>
                    <h3 className="text-lg font-black">Calendar</h3>
                    <p className="text-sm font-semibold text-muted-foreground">
                      {calendarEvents.length} scheduled calendar records across 18 months.
                    </p>
                  </div>
                  <Button variant="outline" size="sm" onClick={refreshSchedules}>
                    <RefreshCw data-icon="inline-start" />
                    Refresh
                  </Button>
                </div>
                <div className="min-h-0 flex-1 overflow-y-auto pr-1">
                  <div className="flex flex-col gap-5">
                    {calendarMonths.map((month) => (
                      <div className="grid gap-1" key={month.key}>
                        <h4 className="px-1 text-base font-black">
                          {calendarMonthLabel(month.date)}
                        </h4>
                        <div className="grid grid-cols-7 gap-1 text-center text-xs font-black text-muted-foreground">
                          {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((day) => (
                            <div className="py-2" key={day}>
                              {day}
                            </div>
                          ))}
                        </div>
                        <div className="grid grid-cols-7 gap-1">
                          {month.days.filter((day) => day.inMonth).map((day, index) => {
                            const events = calendarEventsByDay.get(day.key) ?? [];
                            const isSelected = selectedCalendarDay === day.key;
                            return (
                              <button
                                type="button"
                                className={cn(
                                  "flex min-h-24 flex-col items-start gap-1 rounded-xl border p-2 text-left transition",
                                  isSelected
                                    ? "border-primary bg-secondary"
                                    : "border-border",
                                  events.length > 0 ? "hover:bg-secondary" : "cursor-default"
                                )}
                                key={`${month.key}-${day.key}`}
                                style={
                                  index === 0
                                    ? { gridColumnStart: day.date.getDay() + 1 }
                                    : undefined
                                }
                                onClick={() => {
                                  if (events.length > 0) {
                                    setSelectedCalendarDay(day.key);
                                    setExpandedCalendarEventUri(null);
                                  }
                                }}
                              >
                                <span className="text-xs font-black">
                                  {day.date.getDate()}
                                </span>
                                {events.slice(0, 2).map((event) => (
                                  <span
                                    className="line-clamp-2 w-full rounded-lg bg-muted px-2 py-1 text-[11px] font-bold leading-4"
                                    key={event.source.uri}
                                  >
                                    {event.name}
                                  </span>
                                ))}
                                {events.length > 2 ? (
                                  <span className="text-[11px] font-black text-muted-foreground">
                                    +{events.length - 2} more
                                  </span>
                                ) : null}
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </section>

              <section className="flex min-h-0 flex-col gap-3 overflow-y-auto rounded-[1.5rem] border border-border bg-background/50 p-3 sm:p-4">
                <div>
                  <h3 className="text-lg font-black">Day Agenda</h3>
                  <p className="text-sm font-semibold text-muted-foreground">
                    ATmosphere-ready calendar records for scheduled content.
                  </p>
                </div>
                {selectedCalendarEvents.length === 0 ? (
                  <div className="rounded-xl bg-muted px-3 py-3 text-sm font-semibold text-muted-foreground">
                    Pick a scheduled day to inspect its records.
                  </div>
                ) : (
                  selectedCalendarEvents.map((event) => {
                    const isExpanded = expandedCalendarEventUri === event.source.uri;
                    return (
                      <article
                        className={cn(
                          "flex flex-col gap-3 rounded-[1.25rem] border bg-card p-4 transition",
                          isExpanded ? "border-primary bg-secondary" : "border-border"
                        )}
                        key={event.source.uri}
                      >
                        <button
                          type="button"
                          className="flex w-full items-start justify-between gap-3 text-left"
                          aria-expanded={isExpanded}
                          onClick={() => {
                            setSelectedRkey(event.source.rkey);
                            setExpandedCalendarEventUri(isExpanded ? null : event.source.uri);
                          }}
                        >
                          <div>
                            <div className="line-clamp-2 text-sm font-black">{event.name}</div>
                            <div className="text-xs font-semibold text-muted-foreground">
                              {formatSchedule(event.startsAt)}
                            </div>
                          </div>
                          <Badge variant={statusVariant(event.status)}>
                            {statusLabel(event.status)}
                          </Badge>
                        </button>
                        {isExpanded ? (
                          <div className="flex flex-col gap-3">
                            {event.description ? (
                              <div className="rounded-xl bg-card/80 px-3 py-2 text-sm font-semibold leading-6">
                                {event.description}
                              </div>
                            ) : null}
                            <div className="grid grid-cols-2 gap-2 text-xs font-bold text-muted-foreground">
                              <div className="rounded-xl bg-muted px-3 py-2">
                                Type
                                <span className="block truncate text-foreground">
                                  {event.content?.recordType}
                                </span>
                              </div>
                              <div className="rounded-xl bg-muted px-3 py-2">
                                Timezone
                                <span className="block truncate text-foreground">
                                  {event.timezone ?? "UTC"}
                                </span>
                              </div>
                            </div>
                            <div className="rounded-xl bg-muted px-3 py-2 text-xs font-bold text-muted-foreground">
                              Source Schedule
                              <span className="block break-all text-foreground">
                                {event.source.uri}
                              </span>
                            </div>
                            <details className="rounded-xl bg-muted px-3 py-2 text-xs font-semibold text-muted-foreground">
                              <summary className="cursor-pointer font-black text-foreground">
                                Calendar Record
                              </summary>
                              <pre className="mt-2 max-h-48 overflow-auto whitespace-pre-wrap break-words rounded-lg bg-background/70 p-2 text-[11px]">
                                {JSON.stringify(event, null, 2)}
                              </pre>
                            </details>
                          </div>
                        ) : null}
                      </article>
                    );
                  })
                )}
              </section>
            </div>
          </div>
        </div>
      ) : null}

      {scheduleOpen ? (
        <div
          aria-labelledby="schedule-sheet-title"
          aria-modal="true"
          className="fixed inset-0 z-[100] bg-foreground/30 p-4 backdrop-blur-sm"
          role="dialog"
        >
          <div className="mx-auto mt-[12dvh] flex max-w-md flex-col gap-4 rounded-[2rem] border border-border bg-card p-5 shadow-[0_16px_48px_rgba(35,31,32,0.18)]">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-xl font-black" id="schedule-sheet-title">
                  Schedule
                </h2>
                <p className="text-sm font-semibold text-muted-foreground">
                  Pick when Skej should publish.
                </p>
              </div>
              <Button
                variant="ghost"
                size="icon"
                aria-label="Close Schedule Sheet"
                onClick={() => setScheduleOpen(false)}
              >
                <X />
              </Button>
            </div>
            <label className="flex flex-col gap-2">
              <span className="text-sm font-black">Date and Time</span>
              <div className="relative rounded-2xl border border-input bg-card shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition focus-within:ring-2 focus-within:ring-ring">
                <Input
                  className="skej-date-control border-0 bg-transparent pr-12 focus-visible:ring-0"
                  type="datetime-local"
                  value={draft.scheduledFor}
                  onChange={(event) =>
                    setDraft((current) => ({
                      ...current,
                      scheduledFor: event.target.value,
                    }))
                  }
                />
                <CalendarClock
                  aria-hidden="true"
                  className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                />
              </div>
            </label>
            <div className="rounded-2xl bg-secondary p-4 text-sm font-semibold text-secondary-foreground">
              Skej keeps this draft ready until the scheduled time.
            </div>
            <Button
              disabled={issues.length > 0 || firstPostCount === 0 || !canCreateForSelectedBrand}
              onClick={scheduleDraft}
            >
              <CalendarClock data-icon="inline-start" />
              {editingRkey ? "Save update" : canApproveSelectedBrand ? "Schedule post" : "Propose post"}
            </Button>
          </div>
        </div>
      ) : null}
    </main>
  );
}
