"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import * as React from "react";
import { AlertCircle, ArrowLeft, BarChart3, Check, Clock3, RefreshCw } from "lucide-react";

import { AuthenticatedNav } from "@/components/AuthenticatedNav";
import { SkejLogoMark } from "@/components/SkejLogoMark";
import { ThemeToggle } from "@/components/ThemeToggle";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getEngagement } from "@/lib/analyticsApi";
import type {
  EngagementAccountIdentity,
  EngagementBucket,
  EngagementMetric,
  GetEngagementOutput,
} from "@/lib/analyticsTypes";
import { cn } from "@/lib/utils";

const EngagementCharts = dynamic(
  () => import("@/components/analytics/EngagementCharts").then((module) => module.EngagementCharts),
  {
    ssr: false,
    loading: () => <div className="h-[22rem] animate-pulse rounded-[1.5rem] bg-muted" />,
  }
);

const RANGES = [7, 30, 90] as const;
const METRICS: EngagementMetric[] = ["total", "likes", "reposts", "replies", "quotes", "bookmarks"];

function parseRange(value: string | null): (typeof RANGES)[number] {
  const parsed = Number(value?.replace("d", ""));
  return RANGES.includes(parsed as (typeof RANGES)[number]) ? (parsed as (typeof RANGES)[number]) : 30;
}

function parseBucket(value: string | null): EngagementBucket {
  return value === "week" ? "week" : "day";
}

function parseMetric(value: string | null): EngagementMetric {
  return METRICS.includes(value as EngagementMetric) ? (value as EngagementMetric) : "total";
}

function accountName(account: EngagementAccountIdentity) {
  return account.displayName ?? account.handle ?? account.did;
}

function formatTimestamp(value?: string) {
  if (!value) return "Not collected yet";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export function AnalyticsDashboard() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const range = parseRange(searchParams.get("range"));
  const bucket = parseBucket(searchParams.get("bucket"));
  const metric = parseMetric(searchParams.get("metric"));
  const selectedAccountDids = React.useMemo(
    () => new Set((searchParams.get("accounts") ?? "").split(",").filter(Boolean)),
    [searchParams]
  );
  const [analytics, setAnalytics] = React.useState<GetEngagementOutput | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);

  const replaceParameters = React.useCallback(
    (updates: Record<string, string | null>) => {
      const next = new URLSearchParams(searchParams.toString());
      for (const [key, value] of Object.entries(updates)) {
        if (value === null) next.delete(key);
        else next.set(key, value);
      }
      const query = next.toString();
      setLoading(true);
      setError(null);
      router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
    },
    [pathname, router, searchParams]
  );

  const requestData = React.useCallback(async (signal?: AbortSignal) => {
    const to = new Date();
    const from = new Date(to.getTime() - range * 24 * 60 * 60 * 1000);
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
    return getEngagement(
      {
        from: from.toISOString(),
        to: to.toISOString(),
        bucket,
        timezone,
      },
      signal
    );
  }, [bucket, range]);

  React.useEffect(() => {
    const controller = new AbortController();
    void requestData(controller.signal)
      .then((output) => {
        setAnalytics(output);
        setLoading(false);
      })
      .catch((loadError: unknown) => {
        if (controller.signal.aborted) return;
        setError(loadError instanceof Error ? loadError.message : "Skej could not load analytics.");
        setLoading(false);
      });
    return () => controller.abort();
  }, [requestData]);

  async function refresh() {
    setLoading(true);
    setError(null);
    try {
      const output = await requestData();
      setAnalytics(output);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Skej could not load analytics.");
    } finally {
      setLoading(false);
    }
  }

  const accounts = React.useMemo(
    () => analytics?.accounts.map((series) => series.account) ?? [],
    [analytics]
  );
  const visibleDids = React.useMemo(
    () => {
      const available = new Set(accounts.map((account) => account.did));
      const selected = new Set(Array.from(selectedAccountDids).filter((did) => available.has(did)));
      return selected.size > 0 ? selected : available;
    },
    [accounts, selectedAccountDids]
  );
  const visibleAnalytics = React.useMemo(
    () => analytics?.accounts.filter((series) => visibleDids.has(series.account.did)) ?? [],
    [analytics, visibleDids]
  );
  const periodTotal = visibleAnalytics.reduce((sum, account) => sum + account.period.total, 0);
  const trackedPosts = visibleAnalytics.reduce((sum, account) => sum + account.trackedPostCount, 0);

  function toggleAccount(did: string) {
    const next = new Set(visibleDids);
    if (next.has(did)) next.delete(did);
    else next.add(did);
    if (next.size === 0) return;
    const allDids = new Set(accounts.map((account) => account.did));
    const isAll = next.size === allDids.size && Array.from(next).every((item) => allDids.has(item));
    replaceParameters({ accounts: isAll ? null : Array.from(next).sort().join(",") });
  }

  return (
    <main className="min-h-dvh px-4 pb-16 pt-4 text-foreground sm:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-5">
        <header className="sticky top-11 z-40 flex items-center justify-between gap-3 rounded-[2rem] border border-border bg-card/95 px-4 py-3 shadow-[0_14px_38px_rgba(35,31,32,0.08)] backdrop-blur">
          <Link className="flex min-w-0 items-center gap-3" href="/app">
            <SkejLogoMark />
            <div className="flex min-w-0 flex-col">
              <span className="text-2xl font-black text-primary">Skej</span>
              <span className="truncate text-xs font-bold text-muted-foreground">Engagement Analytics</span>
            </div>
          </Link>
          <div className="flex items-center gap-2">
            <ThemeToggle />
            <Link className={buttonVariants({ size: "sm", variant: "outline" })} href="/app">
              <ArrowLeft data-icon="inline-start" />
              Workspace
            </Link>
          </div>
        </header>
        <AuthenticatedNav />

        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <CardTitle className="flex items-center gap-2">
                  <BarChart3 /> Unified engagement
                </CardTitle>
                <CardDescription>
                  Net Bluesky engagement across every account you can access. Total excludes bookmarks.
                </CardDescription>
              </div>
              <Button disabled={loading} onClick={() => void refresh()} size="sm" variant="outline">
                <RefreshCw className={cn(loading && "animate-spin")} data-icon="inline-start" />
                Refresh
              </Button>
            </div>
          </CardHeader>
          <CardContent className="grid gap-5">
            <div className="grid gap-4 lg:grid-cols-[auto_auto_minmax(0,1fr)]">
              <fieldset>
                <legend className="mb-2 text-xs font-black uppercase tracking-wide text-muted-foreground">Range</legend>
                <div className="flex rounded-full bg-muted p-1">
                  {RANGES.map((days) => (
                    <button
                      aria-pressed={range === days}
                      className={cn("min-h-11 rounded-full px-4 text-sm font-black", range === days && "bg-card shadow-sm")}
                      key={days}
                      onClick={() => replaceParameters({ range: days === 30 ? null : `${days}d` })}
                      type="button"
                    >
                      {days}d
                    </button>
                  ))}
                </div>
              </fieldset>
              <fieldset>
                <legend className="mb-2 text-xs font-black uppercase tracking-wide text-muted-foreground">Bucket</legend>
                <div className="flex rounded-full bg-muted p-1">
                  {(["day", "week"] as const).map((item) => (
                    <button
                      aria-pressed={bucket === item}
                      className={cn("min-h-11 rounded-full px-4 text-sm font-black capitalize", bucket === item && "bg-card shadow-sm")}
                      key={item}
                      onClick={() => replaceParameters({ bucket: item === "day" ? null : item })}
                      type="button"
                    >
                      {item}
                    </button>
                  ))}
                </div>
              </fieldset>
              <fieldset>
                <legend className="mb-2 text-xs font-black uppercase tracking-wide text-muted-foreground">Line metric</legend>
                <div className="flex flex-wrap gap-2">
                  {METRICS.map((item) => (
                    <button
                      aria-pressed={metric === item}
                      className={cn(
                        "min-h-11 rounded-full border border-border px-3 text-sm font-black capitalize",
                        metric === item && "border-primary bg-primary text-primary-foreground"
                      )}
                      key={item}
                      onClick={() => replaceParameters({ metric: item === "total" ? null : item })}
                      type="button"
                    >
                      {item}
                    </button>
                  ))}
                </div>
              </fieldset>
            </div>

            <fieldset>
              <legend className="mb-2 text-xs font-black uppercase tracking-wide text-muted-foreground">Accounts</legend>
              <div className="flex flex-wrap gap-2">
                {accounts.map((account) => {
                  const selected = visibleDids.has(account.did);
                  return (
                    <button
                      aria-pressed={selected}
                      className={cn(
                        "flex min-h-11 items-center gap-2 rounded-full border border-border px-3 text-sm font-black",
                        selected ? "bg-secondary text-secondary-foreground" : "text-muted-foreground"
                      )}
                      key={account.did}
                      onClick={() => toggleAccount(account.did)}
                      type="button"
                    >
                      {selected ? <Check className="size-4" /> : null}
                      {accountName(account)}
                    </button>
                  );
                })}
              </div>
            </fieldset>
          </CardContent>
        </Card>

        {error ? (
          <div className="flex items-start gap-3 rounded-[1.5rem] border border-destructive/30 bg-muted px-4 py-3 text-sm font-bold text-destructive">
            <AlertCircle className="mt-0.5 shrink-0" /> {error}
          </div>
        ) : null}

        {analytics ? (
          <>
            <div className="grid gap-3 sm:grid-cols-3">
              <Card><CardHeader><CardDescription>Net total</CardDescription><CardTitle>{periodTotal.toLocaleString()}</CardTitle></CardHeader></Card>
              <Card><CardHeader><CardDescription>Tracked posts</CardDescription><CardTitle>{trackedPosts.toLocaleString()}</CardTitle></CardHeader></Card>
              <Card><CardHeader><CardDescription>Accounts</CardDescription><CardTitle>{visibleAnalytics.length}</CardTitle></CardHeader></Card>
            </div>

            <div className="flex flex-wrap items-center gap-2 rounded-[1.25rem] border border-border bg-card px-4 py-3 text-sm font-semibold">
              <Badge variant={analytics.status === "live" ? "success" : analytics.status === "partial" ? "warning" : "secondary"}>
                {analytics.status}
              </Badge>
              <Clock3 className="size-4 text-muted-foreground" />
              Last collected {formatTimestamp(analytics.lastCollectedAt)}
              {analytics.coverageStartedAt ? (
                <span className="text-muted-foreground">Coverage began {formatTimestamp(analytics.coverageStartedAt)}.</span>
              ) : null}
              {analytics.status === "partial" ? (
                <span className="text-muted-foreground">Some posts or metric fields were unavailable; retained history remains included.</span>
              ) : null}
            </div>

            {visibleAnalytics.length > 0 ? (
              <EngagementCharts accounts={visibleAnalytics} metric={metric} />
            ) : (
              <Card><CardContent className="p-6 text-sm font-semibold text-muted-foreground">No authored posts were found in this range yet.</CardContent></Card>
            )}

            <details className="rounded-[1.5rem] border border-border bg-card p-4">
              <summary className="cursor-pointer text-base font-black">Full accessible data table</summary>
              <p className="mt-2 text-sm font-semibold text-muted-foreground">
                Every plotted value is available without hover. Values are signed net changes.
              </p>
              <div className="mt-4 overflow-x-auto">
                <table className="w-full min-w-[54rem] border-collapse text-left text-sm">
                  <caption className="sr-only">Engagement values by account and time bucket</caption>
                  <thead>
                    <tr className="border-b border-border">
                      {[
                        "Account", "Bucket", "Total", "Likes", "Reposts", "Replies", "Quotes", "Bookmarks",
                      ].map((heading) => <th className="px-3 py-2 font-black" key={heading} scope="col">{heading}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {visibleAnalytics.flatMap((series) =>
                      series.points.map((point) => (
                        <tr className="border-b border-border/70" key={`${series.account.did}-${point.bucketStart}`}>
                          <th className="px-3 py-2 font-black" scope="row">{series.account.displayName ?? series.account.handle ?? series.account.did}</th>
                          <td className="px-3 py-2">{new Date(point.bucketStart).toLocaleDateString()}</td>
                          <td className="px-3 py-2">{point.total.toLocaleString()}</td>
                          <td className="px-3 py-2">{point.likes.toLocaleString()}</td>
                          <td className="px-3 py-2">{point.reposts.toLocaleString()}</td>
                          <td className="px-3 py-2">{point.replies.toLocaleString()}</td>
                          <td className="px-3 py-2">{point.quotes.toLocaleString()}</td>
                          <td className="px-3 py-2">{point.bookmarks.toLocaleString()}</td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </details>
          </>
        ) : loading ? (
          <div className="h-72 animate-pulse rounded-[1.5rem] bg-muted" />
        ) : null}
      </div>
    </main>
  );
}
