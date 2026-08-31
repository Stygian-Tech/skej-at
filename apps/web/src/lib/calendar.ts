export type CalendarEventStatus =
  | "community.lexicon.calendar.event#planned"
  | "community.lexicon.calendar.event#scheduled"
  | "community.lexicon.calendar.event#rescheduled"
  | "community.lexicon.calendar.event#postponed"
  | "community.lexicon.calendar.event#cancelled";

export interface CalendarEventRecord {
  $type: "community.lexicon.calendar.event";
  name: string;
  uris?: Array<{ uri: string; name?: string }>;
  startsAt?: string;
  endsAt?: string;
  status?: CalendarEventStatus;
  mode?: string;
  createdAt: string;
}

export interface CalendarEventSummary {
  accountDid: string;
  rkey: string;
  uri: string;
  cid?: string;
  record: CalendarEventRecord;
}

export interface CalendarAccount {
  did: string;
  handle?: string;
  displayName?: string;
}

export interface CalendarFilters {
  month: string;
  accountDids: string[];
  statuses: CalendarEventStatus[];
}

export const CALENDAR_STATUSES: Array<{
  value: CalendarEventStatus;
  label: string;
}> = [
  { value: "community.lexicon.calendar.event#planned", label: "Planned" },
  { value: "community.lexicon.calendar.event#scheduled", label: "Scheduled" },
  { value: "community.lexicon.calendar.event#rescheduled", label: "Rescheduled" },
  { value: "community.lexicon.calendar.event#postponed", label: "Postponed" },
  { value: "community.lexicon.calendar.event#cancelled", label: "Cancelled" },
];

export function currentCalendarMonth(now = new Date()): string {
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}

export function calendarMonthRange(month: string): { from: string; to: string } {
  const match = /^(\d{4})-(\d{2})$/.exec(month);
  const fallback = currentCalendarMonth();
  const [year, monthNumber] = (match ? month : fallback).split("-").map(Number);
  return {
    from: new Date(Date.UTC(year, monthNumber - 1, 1)).toISOString(),
    to: new Date(Date.UTC(year, monthNumber, 1)).toISOString(),
  };
}

export function calendarMonthDays(month: string): Array<{
  key: string;
  day: number;
  weekdayOffset: number;
}> {
  const { from, to } = calendarMonthRange(month);
  const start = new Date(from);
  const dayCount = Math.round((new Date(to).getTime() - start.getTime()) / 86_400_000);
  return Array.from({ length: dayCount }, (_, index) => {
    const date = new Date(start.getTime() + index * 86_400_000);
    return {
      key: date.toISOString().slice(0, 10),
      day: index + 1,
      weekdayOffset: index === 0 ? date.getUTCDay() : 0,
    };
  });
}

export async function listCalendarWorkspace(
  filters: CalendarFilters,
  signal?: AbortSignal
): Promise<{ accounts: CalendarAccount[]; events: CalendarEventSummary[] }> {
  const { from, to } = calendarMonthRange(filters.month);
  const params = new URLSearchParams({ from, to });
  for (const did of filters.accountDids) params.append("accountDids", did);
  for (const status of filters.statuses) params.append("status", status);

  const [accountsResponse, eventsResponse] = await Promise.all([
    fetch("/xrpc/at.skej.account.list", { credentials: "include", signal }),
    fetch(`/xrpc/at.skej.calendar.list?${params}`, { credentials: "include", signal }),
  ]);
  if (!accountsResponse.ok || !eventsResponse.ok) {
    const failure = !eventsResponse.ok ? eventsResponse : accountsResponse;
    const body = (await failure.json().catch(() => null)) as { message?: string } | null;
    throw new Error(body?.message ?? "Skej could not load this calendar.");
  }
  const accountsBody = (await accountsResponse.json()) as { accounts: CalendarAccount[] };
  const eventsBody = (await eventsResponse.json()) as { events: CalendarEventSummary[] };
  return { accounts: accountsBody.accounts, events: eventsBody.events };
}
