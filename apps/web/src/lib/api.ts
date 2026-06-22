import { ComposerDraft, buildScheduleRecord } from "@/lib/editor";
import { ScheduledPostSummary, Viewer } from "@/lib/skejTypes";

async function requestJSON<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, {
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    ...init,
  });

  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as
      | { message?: string; error?: string }
      | null;
    throw new Error(body?.message ?? body?.error ?? `Request failed (${response.status})`);
  }

  return (await response.json()) as T;
}

export function startOAuth(handle: string): string {
  const params = new URLSearchParams();
  params.set("handle", handle.trim());
  return `/oauth/start?${params.toString()}`;
}

export async function getViewer(): Promise<Viewer> {
  return requestJSON<Viewer>("/v1/me");
}

export async function listSchedules(): Promise<ScheduledPostSummary[]> {
  const body = await requestJSON<{ records: ScheduledPostSummary[] }>("/v1/schedules");
  return body.records;
}

export async function createSchedule(
  draft: ComposerDraft
): Promise<ScheduledPostSummary> {
  const record = buildScheduleRecord(draft);
  return requestJSON<ScheduledPostSummary>("/v1/schedules", {
    method: "POST",
    body: JSON.stringify({ record }),
  });
}

export async function updateSchedule(
  rkey: string,
  draft: ComposerDraft
): Promise<ScheduledPostSummary> {
  const record = buildScheduleRecord(draft);
  return requestJSON<ScheduledPostSummary>(`/v1/schedules/${encodeURIComponent(rkey)}`, {
    method: "PATCH",
    body: JSON.stringify({ record }),
  });
}

export async function deleteSchedule(rkey: string): Promise<void> {
  await requestJSON<{ ok: boolean }>(`/v1/schedules/${encodeURIComponent(rkey)}`, {
    method: "DELETE",
  });
}

export async function publishNow(rkey: string): Promise<ScheduledPostSummary> {
  return requestJSON<ScheduledPostSummary>(
    `/v1/schedules/${encodeURIComponent(rkey)}/publish-now`,
    {
      method: "POST",
    }
  );
}

