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

import { AuthenticatedNav } from "@/components/AuthenticatedNav";
import { OAuthLoginForm } from "@/components/OAuthLoginForm";
import { SkejLogoMark } from "@/components/SkejLogoMark";
import {
  SocialMarkdownEditor,
  SocialMarkdownPreview,
} from "@/components/SocialMarkdownEditor";
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
import {
  createSchedule,
  cancelSchedule,
  duplicateSchedule,
  getViewer,
  hydrateLinkPreview,
  isReauthRequired,
  listAccountSchedules,
  listAccounts,
  listSchedules,
  logout,
  publishNow,
  recordScheduleView,
  retrySchedule,
  startOAuth,
  updateSchedule,
} from "@/lib/api";
import {
  ComposerDraft,
  MAX_POST_GRAPHEMES,
  MAX_SCHEDULE_TITLE_GRAPHEMES,
  countGraphemes,
  firstPostLinkURL,
  generateTID,
  localDatetimeValue,
  validateComposerDraft,
} from "@/lib/editor";
import {
  LINK_PREVIEW_DEBOUNCE_MS,
  automaticLinkPreviewURL,
  canApplyAutomaticLinkPreview,
  shouldRemoveAutomaticLinkPreview,
} from "@/lib/linkPreview";
import { projectMarkdownPost } from "@/lib/socialMarkdown";
import { cn } from "@/lib/utils";
import {
  ManagedAccount,
  PostPlan,
  ScheduledPostSummary,
  Viewer,
} from "@/lib/skejTypes";

type AuthStatus = "loading" | "anonymous" | "authenticated";
type QueueMode = "upcoming" | "history";
type LinkPreviewStatus =
  | { state: "loading"; url: string }
  | { state: "ready"; url: string }
  | { state: "error"; url: string; message: string };

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
        source: { format: "markdown", text: "" },
        text: "",
        publishRkey: generateTID(),
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
    posts: [
      {
        source: { format: "markdown", text: "" },
        text: "",
        langs: ["en"],
        tags: [],
      },
    ],
  };
}

function draftFromSchedule(
  item: ScheduledPostSummary,
  date = new Date(item.scheduledAt)
): ComposerDraft {
  const first = item.record.posts[0];
  const relationship = item.record.dependency?.relationship;
  return {
    mode:
      relationship === "reply" || relationship === "quote"
        ? relationship
        : first?.reply
          ? "reply"
          : first?.embed?.record
            ? "quote"
            : "post",
    title: item.record.title ?? "",
    scheduledFor: localDatetimeValue(date),
    timezone: item.record.userTimezone,
    dependencyScheduleUri: item.record.dependency?.dependsOnScheduleUri,
    posts: item.record.posts.map((post) =>
      projectMarkdownPost({
        ...post,
        publishRkey: post.publishRkey ?? generateTID(),
        embed: post.embed ? { ...post.embed } : undefined,
      })
    ),
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

function linkHostname(value: string) {
  try {
    return new URL(value).hostname;
  } catch {
    return value;
  }
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
  const first = item.record.posts[0];
  const text = first ? projectMarkdownPost(first).text.trim() : "";
  return item.record.title?.trim() || text || "Untitled post";
}

function calendarDayLabel(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
  }).format(new Date(value));
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

function accountLabel(account: ManagedAccount) {
  return account.handle ?? account.displayName ?? account.did;
}

function needsReauth(account: ManagedAccount | null | undefined) {
  return account?.status === "needs_reauth";
}

/**
 * Reconnecting is just the normal OAuth start with the handle prefilled — the
 * user never has to remember or retype it. Accounts with no handle can't be
 * routed automatically, so those fall back to the sign-in form.
 */
function reconnectAccount(account: ManagedAccount) {
  if (!account.handle) {
    window.location.href = "/app#connect-account";
    return;
  }
  window.location.href = startOAuth(account.handle);
}

function ReconnectBanner({
  accounts,
  selectedAccountDid,
}: {
  accounts: ManagedAccount[];
  selectedAccountDid: string | null;
}) {
  const stale = accounts.filter(needsReauth);
  if (stale.length === 0) return null;

  // The account the user is looking at is the one they can act on right now, so
  // it leads; any others are named so a reconnect doesn't feel like whack-a-mole.
  const primary = stale.find((account) => account.did === selectedAccountDid) ?? stale[0];
  const others = stale.filter((account) => account.did !== primary.did);

  return (
    <div
      className="flex flex-col gap-3 rounded-[1.5rem] border border-destructive/30 bg-muted px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
      role="status"
    >
      <div className="flex items-start gap-3">
        <AlertCircle className="mt-0.5 shrink-0 text-destructive" />
        <div className="flex flex-col gap-1">
          <p className="text-sm font-bold text-destructive">
            Bluesky needs you to reconnect {accountLabel(primary)}.
          </p>
          <p className="text-xs font-semibold text-muted-foreground">
            Scheduled posts stay queued and publish once you reconnect. You may be
            seeing a slightly stale queue until then.
            {others.length > 0
              ? ` Also waiting: ${others.map(accountLabel).join(", ")}.`
              : ""}
          </p>
        </div>
      </div>
      <Button
        className="shrink-0"
        onClick={() => reconnectAccount(primary)}
        size="sm"
      >
        <RefreshCw data-icon="inline-start" />
        Reconnect
      </Button>
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
  const [selectedRkey, setSelectedRkey] = React.useState<string | null>(null);
  const [editingRkey, setEditingRkey] = React.useState<string | null>(null);
  const [isQueueLoading, setIsQueueLoading] = React.useState(false);
  const [isMutating, setIsMutating] = React.useState(false);
  const [actionError, setActionError] = React.useState<string | null>(null);
  const [actionMessage, setActionMessage] = React.useState<string | null>(null);
  const [profileOpen, setProfileOpen] = React.useState(false);
  const [linkPreviewStatuses, setLinkPreviewStatuses] = React.useState<
    Record<number, LinkPreviewStatus>
  >({});
  const [linkPreviewRetryNonce, setLinkPreviewRetryNonce] = React.useState(0);
  const automaticLinkURLs = React.useRef(new Map<number, string>());
  const automaticLinkAccounts = React.useRef(new Map<number, string>());
  const suppressedLinkURLs = React.useRef(new Map<number, string>());

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
  const proEnabled = viewer?.proFeaturesEnabled === true;
  const selectedAccount =
    accounts.find((account) => account.did === selectedAccountDid) ?? accounts[0] ?? null;
  // When capability wiring lands, both must be forced true while `proEnabled`
  // is false so posts always schedule directly instead of entering a draft
  // state nobody can approve.
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
      // Listing schedules is what makes the API notice dead credentials, so this
      // is the moment the account status can have changed. Re-reading it here is
      // what lets the banner appear without a page reload.
      setAccounts(await listAccounts());
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
    if (!selectedAccountDid) return;

    const timers: number[] = [];
    const controllers: AbortController[] = [];

    draft.posts.forEach((post, index) => {
      const url = automaticLinkPreviewURL(post);
      const previousAutomaticURL = automaticLinkURLs.current.get(index);

      if (!url) {
        suppressedLinkURLs.current.delete(index);
        if (shouldRemoveAutomaticLinkPreview(post, previousAutomaticURL)) {
          automaticLinkURLs.current.delete(index);
          automaticLinkAccounts.current.delete(index);
          setDraft((current) => ({
            ...current,
            posts: current.posts.map((entry, entryIndex) =>
              entryIndex === index ? { ...entry, embed: undefined } : entry
            ),
          }));
        }
        setLinkPreviewStatuses((current) => {
          if (!(index in current)) return current;
          const next = { ...current };
          delete next[index];
          return next;
        });
        return;
      }

      if (suppressedLinkURLs.current.get(index) === url) return;
      if (suppressedLinkURLs.current.get(index) !== url) {
        suppressedLinkURLs.current.delete(index);
      }
      if (
        post.embed?.external &&
        !previousAutomaticURL
      ) {
        return;
      }
      if (
        previousAutomaticURL === url &&
        automaticLinkAccounts.current.get(index) === selectedAccountDid &&
        post.embed?.external?.uri === url
      ) {
        return;
      }

      setLinkPreviewStatuses((current) => ({
        ...current,
        [index]: { state: "loading", url },
      }));
      const controller = new AbortController();
      controllers.push(controller);
      timers.push(
        window.setTimeout(() => {
          void hydrateLinkPreview(selectedAccountDid, url, controller.signal)
            .then((embed) => {
              if (controller.signal.aborted) return;
              automaticLinkURLs.current.set(index, url);
              automaticLinkAccounts.current.set(index, selectedAccountDid);
              setDraft((current) => ({
                ...current,
                posts: current.posts.map((entry, entryIndex) => {
                  if (
                    entryIndex !== index ||
                    !canApplyAutomaticLinkPreview(
                      entry,
                      url,
                      previousAutomaticURL
                    )
                  ) {
                    return entry;
                  }
                  return { ...entry, embed };
                }),
              }));
              setLinkPreviewStatuses((current) => ({
                ...current,
                [index]: { state: "ready", url },
              }));
            })
            .catch((error: unknown) => {
              if (controller.signal.aborted) return;
              setLinkPreviewStatuses((current) => ({
                ...current,
                [index]: {
                  state: "error",
                  url,
                  message:
                    error instanceof Error
                      ? error.message
                      : "The preview could not be loaded.",
                },
              }));
            });
        }, LINK_PREVIEW_DEBOUNCE_MS)
      );
    });

    return () => {
      timers.forEach(window.clearTimeout);
      controllers.forEach((controller) => controller.abort());
    };
  }, [draft.posts, linkPreviewRetryNonce, selectedAccountDid]);

  function updatePost(index: number, nextPost: PostPlan) {
    setDraft((current) => ({
      ...current,
      posts: current.posts.map((post, postIndex) =>
        postIndex === index ? nextPost : post
      ),
    }));
  }

  function updateFirstPost(updater: (post: PostPlan) => PostPlan) {
    setDraft((current) => {
      const [
        first = {
          source: { format: "markdown" as const, text: "" },
          text: "",
          publishRkey: generateTID(),
          langs: ["en"],
          tags: [],
        },
        ...rest
      ] = current.posts;
      return {
        ...current,
        posts: [updater(first), ...rest],
      };
    });
  }

  function removeThreadPost(index: number) {
    automaticLinkURLs.current.clear();
    automaticLinkAccounts.current.clear();
    suppressedLinkURLs.current.clear();
    setLinkPreviewStatuses({});
    setDraft((current) => ({
      ...current,
      posts: current.posts.filter((_, postIndex) => postIndex !== index),
    }));
  }

  function removeLinkPreview(index: number) {
    const post = draft.posts[index];
    const url = post ? firstPostLinkURL(post) : undefined;
    if (url) suppressedLinkURLs.current.set(index, url);
    automaticLinkURLs.current.delete(index);
    automaticLinkAccounts.current.delete(index);
    setLinkPreviewStatuses((current) => {
      const next = { ...current };
      delete next[index];
      return next;
    });
    setDraft((current) => ({
      ...current,
      posts: current.posts.map((post, postIndex) =>
        postIndex === index ? { ...post, embed: undefined } : post
      ),
    }));
  }

  function keepLinkPreviewManual(index: number) {
    const post = draft.posts[index];
    const url = post ? firstPostLinkURL(post) : undefined;
    if (url) suppressedLinkURLs.current.set(index, url);
    automaticLinkURLs.current.delete(index);
    automaticLinkAccounts.current.delete(index);
    setLinkPreviewStatuses((current) => {
      const next = { ...current };
      delete next[index];
      return next;
    });
  }

  function retryLinkPreview(index: number) {
    const post = draft.posts[index];
    const url = post ? firstPostLinkURL(post) : undefined;
    if (url) suppressedLinkURLs.current.delete(index);
    automaticLinkURLs.current.delete(index);
    automaticLinkAccounts.current.delete(index);
    setLinkPreviewRetryNonce((current) => current + 1);
  }

  function resetComposer() {
    automaticLinkURLs.current.clear();
    automaticLinkAccounts.current.clear();
    suppressedLinkURLs.current.clear();
    setLinkPreviewStatuses({});
    setDraft(emptyDraft());
    setEditingRkey(null);
  }

  /**
   * A write rejected for stale PDS credentials is not a failure the user can fix
   * by retrying, so it re-reads the account list to raise the reconnect banner
   * and says what to do instead of surfacing the raw message.
   */
  async function reportActionError(error: unknown, fallback: string) {
    if (isReauthRequired(error)) {
      setActionError("Reconnect this account to keep posting from it.");
      try {
        setAccounts(await listAccounts());
      } catch {
        // The banner is a nicety; never let refreshing it mask the real error.
      }
      return;
    }
    setActionError(error instanceof Error ? friendlyErrorMessage(error.message) : fallback);
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
      await reportActionError(error, "Could not schedule post.");
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
      await reportActionError(error, "Could not retry post.");
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
      await reportActionError(error, "Could not delete schedule.");
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
      await reportActionError(error, "Could not publish post.");
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
      await reportActionError(error, "Could not duplicate schedule.");
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
                    {proEnabled ? (
                      <div className="relative block">
                        <select
                          aria-label="Connected Account"
                          className="skej-select-control h-10 w-28 rounded-full border border-border bg-background/80 py-0 pl-4 pr-10 text-sm font-black leading-none outline-none transition hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring sm:w-44"
                          value={selectedAccountDid ?? ""}
                          onChange={(event) => void switchAccount(event.target.value)}
                        >
                          {accounts.map((account) => (
                            <option key={account.did} value={account.did}>
                              {needsReauth(account)
                                ? `⚠ ${accountLabel(account)}`
                                : accountLabel(account)}
                            </option>
                          ))}
                        </select>
                        <ChevronDown
                          aria-hidden="true"
                          className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                        />
                      </div>
                    ) : (
                      <span className="flex h-10 w-28 items-center truncate rounded-full border border-border bg-background/80 pl-4 pr-4 text-sm font-black leading-none sm:w-44">
                        {selectedAccount?.handle ?? viewer?.handle ?? viewer?.did}
                      </span>
                    )}
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
        {isAuthenticated ? <AuthenticatedNav /> : null}

        <div className="sticky top-[5.75rem] z-30 flex items-center gap-2 rounded-[1.25rem] border border-accent/70 bg-accent px-3 py-2 text-xs font-black text-accent-foreground shadow-[0_10px_28px_rgba(216,188,83,0.18)]">
          <span>Work in progress. Keep a copy of mission-critical content.</span>
        </div>

        {isAuthenticated ? (
          <ReconnectBanner accounts={accounts} selectedAccountDid={selectedAccountDid} />
        ) : null}

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

        <section className="grid min-w-0 gap-5 lg:grid-cols-[minmax(0,1.05fr)_minmax(360px,0.75fr)]">
          <div className="flex min-w-0 flex-col gap-5">
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
                      const previewStatus = linkPreviewStatuses[index];
                      return (
                        <div
                          key={index}
                          className="flex min-w-0 flex-col gap-2 rounded-[1.25rem] border border-border bg-background/60 p-2.5 sm:rounded-[1.5rem] sm:p-3"
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
                          <SocialMarkdownEditor
                            index={index}
                            onChange={(nextPost) => updatePost(index, nextPost)}
                            post={post}
                          />
                          {previewStatus?.state === "loading" ? (
                            <div className="flex items-center gap-2 rounded-2xl bg-muted px-3 py-2 text-xs font-bold text-muted-foreground">
                              <Loader2 className="size-4 animate-spin" />
                              Loading preview for {linkHostname(previewStatus.url)}…
                            </div>
                          ) : null}
                          {previewStatus?.state === "error" ? (
                            <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-border bg-muted px-3 py-2">
                              <span className="text-xs font-bold text-muted-foreground">
                                {previewStatus.message}
                              </span>
                              <Button
                                variant="outline"
                                size="sm"
                                onClick={() => retryLinkPreview(index)}
                              >
                                <RefreshCw data-icon="inline-start" />
                                Retry
                              </Button>
                            </div>
                          ) : null}
                          {post.embed?.external ? (
                            <div className="flex items-start justify-between gap-3 rounded-2xl border border-border bg-card px-3 py-2">
                              <div className="min-w-0">
                                <div className="truncate text-sm font-black">
                                  {post.embed.external.title || post.embed.external.uri}
                                </div>
                                <div className="line-clamp-2 text-xs font-semibold text-muted-foreground">
                                  {post.embed.external.description ||
                                    linkHostname(post.embed.external.uri)}
                                </div>
                              </div>
                              <Button
                                variant="ghost"
                                size="icon"
                                aria-label={`Remove link preview from post ${index + 1}`}
                                onClick={() => removeLinkPreview(index)}
                              >
                                <X />
                              </Button>
                            </div>
                          ) : null}
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
                      onClick={() => {
                        keepLinkPreviewManual(0);
                        updateFirstPost((post) => ({
                          ...post,
                          embed: {
                            $type: "app.bsky.embed.images",
                            images: [
                              ...(post.embed?.$type === "app.bsky.embed.images"
                                ? post.embed.images ?? []
                                : []),
                              {
                                id: `draft-image-${Date.now()}`,
                                alt: "",
                                previewUrl: "/icon.png",
                              },
                            ],
                          },
                        }));
                      }}
                    >
                      <ImagePlus data-icon="inline-start" />
                      Images
                    </Button>
                    <Button
                      variant="outline"
                      onClick={() => {
                        keepLinkPreviewManual(0);
                        updateFirstPost((post) => ({
                          ...post,
                          embed: {
                            $type: "app.bsky.embed.external",
                            external: post.embed?.external ?? {
                              uri: "https://skej.at",
                              title: "Skej",
                              description: "Plan Bluesky posts ahead with Skej.",
                            },
                          },
                        }));
                      }}
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
                        onChange={(event) => {
                          keepLinkPreviewManual(0);
                          updateFirstPost((post) => ({
                            ...post,
                            embed: {
                              ...post.embed,
                              $type: "app.bsky.embed.external",
                              external: {
                                ...(post.embed?.external ?? { uri: "" }),
                                uri: event.target.value,
                              },
                            },
                          }));
                        }}
                      />
                      <div className="grid gap-3 sm:grid-cols-2">
                        <Input
                          aria-label="External title"
                          placeholder="Link title"
                          value={draft.posts[0].embed.external.title ?? ""}
                          onChange={(event) => {
                            keepLinkPreviewManual(0);
                            updateFirstPost((post) => ({
                              ...post,
                              embed: {
                                ...post.embed,
                                $type: "app.bsky.embed.external",
                                external: {
                                  ...(post.embed?.external ?? { uri: "" }),
                                  title: event.target.value,
                                },
                              },
                            }));
                          }}
                        />
                        <Input
                          aria-label="External description"
                          placeholder="Link description"
                          value={draft.posts[0].embed.external.description ?? ""}
                          onChange={(event) => {
                            keepLinkPreviewManual(0);
                            updateFirstPost((post) => ({
                              ...post,
                              embed: {
                                ...post.embed,
                                $type: "app.bsky.embed.external",
                                external: {
                                  ...(post.embed?.external ?? { uri: "" }),
                                  description: event.target.value,
                                },
                              },
                            }));
                          }}
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

          <aside className="flex min-w-0 flex-col gap-5">
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
                    {proEnabled ? (
                      <Link
                        aria-disabled={!isAuthenticated}
                        className={cn(
                          "inline-flex min-h-8 items-center justify-center gap-2 rounded-lg border px-3 text-xs font-black transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                          !isAuthenticated && "pointer-events-none opacity-50"
                        )}
                        href="/app/calendar"
                      >
                        <ArrowUpRight data-icon="inline-start" />
                        Calendar
                      </Link>
                    ) : null}
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
                {!proEnabled ? null : calendarDays.length > 0 ? (
                  <div className="flex gap-2 overflow-x-auto pb-1">
                    {calendarDays.map(([day, count]) => (
                      <Link
                        className="flex min-w-24 items-center justify-between gap-3 rounded-full bg-muted px-3 py-2 text-left text-xs font-bold transition hover:bg-secondary"
                        href="/app/calendar"
                        key={day}
                      >
                        <span>{day}</span>
                        <span>{count}</span>
                      </Link>
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
                      {selected.record.posts[0] ? (
                        <SocialMarkdownPreview
                          className="line-clamp-3 text-sm font-semibold leading-6"
                          post={selected.record.posts[0]}
                        />
                      ) : null}
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
