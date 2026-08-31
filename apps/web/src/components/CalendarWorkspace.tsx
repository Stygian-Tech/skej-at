"use client";

import { useRouter, useSearchParams } from "next/navigation";
import * as React from "react";

import { AuthenticatedNav } from "@/components/AuthenticatedNav";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  CALENDAR_STATUSES,
  CalendarEventStatus,
  CalendarEventSummary,
  CalendarFilters,
  calendarMonthDays,
  currentCalendarMonth,
  listCalendarWorkspace,
} from "@/lib/calendar";

function statusLabel(status?: CalendarEventStatus): string {
  return CALENDAR_STATUSES.find((entry) => entry.value === status)?.label ?? "Unknown";
}

function shortAccount(did: string): string {
  return did.length > 24 ? `${did.slice(0, 14)}…${did.slice(-6)}` : did;
}

export function CalendarWorkspace() {
  const router = useRouter();
  const search = useSearchParams();
  const month = search.get("month") ?? currentCalendarMonth();
  const accountSelection = search.get("accounts") ?? "";
  const statusSelection = search.get("status") ?? "";
  const accountDids = accountSelection.split(",").filter(Boolean);
  const statuses = statusSelection.split(",").filter(Boolean) as CalendarEventStatus[];
  const [data, setData] = React.useState<Awaited<ReturnType<typeof listCalendarWorkspace>> | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    const controller = new AbortController();
    const filters: CalendarFilters = {
      month,
      accountDids: accountSelection.split(",").filter(Boolean),
      statuses: statusSelection.split(",").filter(Boolean) as CalendarEventStatus[],
    };
    void listCalendarWorkspace(filters, controller.signal)
      .then((result) => {
        setData(result);
        setError(null);
      })
      .catch((reason: unknown) => {
        if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : "Calendar unavailable.");
      });
    return () => controller.abort();
  }, [accountSelection, month, statusSelection]);

  function update(next: Partial<CalendarFilters>) {
    const value: CalendarFilters = { month, accountDids, statuses, ...next };
    const params = new URLSearchParams();
    if (value.month !== currentCalendarMonth()) params.set("month", value.month);
    if (value.accountDids.length) params.set("accounts", value.accountDids.join(","));
    if (value.statuses.length) params.set("status", value.statuses.join(","));
    router.replace(`/app/calendar${params.size ? `?${params}` : ""}`);
  }

  const byDay = React.useMemo(() => {
    const grouped = new Map<string, CalendarEventSummary[]>();
    for (const event of data?.events ?? []) {
      if (!event.record.startsAt) continue;
      const key = event.record.startsAt.slice(0, 10);
      grouped.set(key, [...(grouped.get(key) ?? []), event]);
    }
    return grouped;
  }, [data]);

  return (
    <main className="mx-auto min-h-dvh w-full max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <AuthenticatedNav className="mb-8" />

      <header className="mb-8">
        <Badge variant="secondary">Public AT calendar metadata</Badge>
        <h1 className="mt-3 text-4xl font-black tracking-tight">Calendar</h1>
        <p className="mt-2 max-w-3xl text-muted-foreground">
          Every proposal and schedule has a public metadata-only calendar record. Draft post text is never included.
        </p>
      </header>

      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Filters</CardTitle>
          <CardDescription>Selections are stored in the URL so this view can be shared and restored.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-5 md:grid-cols-[12rem_1fr]">
          <label className="grid gap-2 text-sm font-bold">
            Month
            <input
              className="rounded-xl border bg-background px-3 py-2"
              onChange={(event) => update({ month: event.target.value })}
              type="month"
              value={month}
            />
          </label>
          <fieldset>
            <legend className="mb-2 text-sm font-bold">Accounts</legend>
            <div className="flex flex-wrap gap-2">
              {(data?.accounts ?? []).map((account) => {
                const selected = accountDids.length === 0 || accountDids.includes(account.did);
                return (
                  <Button
                    aria-pressed={selected}
                    key={account.did}
                    onClick={() => {
                      const baseline = accountDids.length === 0 ? (data?.accounts.map((item) => item.did) ?? []) : accountDids;
                      const next = selected ? baseline.filter((did) => did !== account.did) : [...baseline, account.did];
                      update({ accountDids: next.length === data?.accounts.length ? [] : next });
                    }}
                    type="button"
                    variant={selected ? "default" : "outline"}
                  >
                    {account.displayName ?? account.handle ?? shortAccount(account.did)}
                  </Button>
                );
              })}
            </div>
          </fieldset>
          <fieldset className="md:col-span-2">
            <legend className="mb-2 text-sm font-bold">Status</legend>
            <div className="flex flex-wrap gap-2">
              {CALENDAR_STATUSES.map((entry) => {
                const selected = statuses.length === 0 || statuses.includes(entry.value);
                return (
                  <Button
                    aria-pressed={selected}
                    key={entry.value}
                    onClick={() => {
                      const all = CALENDAR_STATUSES.map((item) => item.value);
                      const baseline = statuses.length === 0 ? all : statuses;
                      const next = selected ? baseline.filter((value) => value !== entry.value) : [...baseline, entry.value];
                      update({ statuses: next.length === all.length ? [] : next });
                    }}
                    type="button"
                    variant={selected ? "secondary" : "outline"}
                  >
                    {entry.label}
                  </Button>
                );
              })}
            </div>
          </fieldset>
        </CardContent>
      </Card>

      {error ? <p className="mb-5 rounded-xl border border-destructive p-4 text-destructive" role="alert">{error}</p> : null}

      <section aria-label={`${month} calendar`} className="grid grid-cols-7 gap-1 sm:gap-3">
        {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((day) => (
          <div className="pb-2 text-center text-xs font-black uppercase text-muted-foreground" key={day}>{day}</div>
        ))}
        {calendarMonthDays(month).map((day) => (
          <React.Fragment key={day.key}>
            {day.weekdayOffset > 0 ? Array.from({ length: day.weekdayOffset }, (_, index) => <div aria-hidden="true" key={`pad-${index}`} />) : null}
            <article className="min-h-28 rounded-xl border bg-card p-2 sm:min-h-36 sm:p-3">
              <h2 className="text-sm font-black">{day.day}</h2>
              <div className="mt-2 grid gap-2">
                {(byDay.get(day.key) ?? []).map((event) => (
                  <a className="rounded-lg bg-secondary p-2 text-xs focus-visible:outline focus-visible:outline-2 focus-visible:outline-ring" href={event.uri} key={`${event.accountDid}:${event.rkey}`}>
                    <span className="block font-black">{event.record.name}</span>
                    <span className="block text-muted-foreground">{statusLabel(event.record.status)} · {shortAccount(event.accountDid)}</span>
                  </a>
                ))}
              </div>
            </article>
          </React.Fragment>
        ))}
      </section>
    </main>
  );
}
