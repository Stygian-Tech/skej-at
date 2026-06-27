import { ComposerDraft, buildScheduleRecord } from "@/lib/editor";
import {
  AuditEvent,
  BrandCapability,
  BrandGrantSummary,
  BrandProfile,
  BrandSummary,
  GrantGranteeType,
  ManagedAccount,
  ScheduleStatus,
  ScheduledPostSummary,
  TeamGroupSummary,
  TeamMemberSummary,
  TeamRole,
  TeamSummary,
  Viewer,
} from "@/lib/skejTypes";

function didPath(did: string): string {
  return did;
}

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
    throw new Error(
      body?.message ?? body?.error ?? "Skej could not load this right now. Try again soon."
    );
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

export async function logout(): Promise<void> {
  await requestJSON<{ ok: boolean }>("/v1/logout", {
    method: "POST",
  });
}

export async function listSchedules(): Promise<ScheduledPostSummary[]> {
  const body = await requestJSON<{ records: ScheduledPostSummary[] }>("/v1/schedules");
  return body.records;
}

export async function listAccounts(): Promise<ManagedAccount[]> {
  const body = await requestJSON<{ accounts: ManagedAccount[] }>("/v1/accounts");
  return body.accounts;
}

export async function listTeams(): Promise<TeamSummary[]> {
  const body = await requestJSON<{ teams: TeamSummary[] }>("/v1/teams");
  return body.teams;
}

export async function createTeam(title: string): Promise<TeamSummary> {
  return requestJSON<TeamSummary>("/v1/teams", {
    method: "POST",
    body: JSON.stringify({ title }),
  });
}

export async function listTeamMembers(teamRkey: string): Promise<TeamMemberSummary[]> {
  const body = await requestJSON<{ members: TeamMemberSummary[] }>(
    `/v1/teams/${encodeURIComponent(teamRkey)}/members`
  );
  return body.members;
}

export async function addTeamMember(
  teamRkey: string,
  memberDid: string,
  role: TeamRole
): Promise<TeamMemberSummary> {
  return requestJSON<TeamMemberSummary>(
    `/v1/teams/${encodeURIComponent(teamRkey)}/members`,
    {
      method: "POST",
      body: JSON.stringify({ memberDid, role, status: "active", groupUris: [] }),
    }
  );
}

export async function listTeamGroups(teamRkey: string): Promise<TeamGroupSummary[]> {
  const body = await requestJSON<{ groups: TeamGroupSummary[] }>(
    `/v1/teams/${encodeURIComponent(teamRkey)}/groups`
  );
  return body.groups;
}

export async function createTeamGroup(
  teamRkey: string,
  name: string,
  memberDids: string[] = []
): Promise<TeamGroupSummary> {
  return requestJSON<TeamGroupSummary>(
    `/v1/teams/${encodeURIComponent(teamRkey)}/groups`,
    {
      method: "POST",
      body: JSON.stringify({ name, memberDids, brandGrantUris: [] }),
    }
  );
}

export async function listBrandGrants(teamRkey: string): Promise<BrandGrantSummary[]> {
  const body = await requestJSON<{ grants: BrandGrantSummary[] }>(
    `/v1/teams/${encodeURIComponent(teamRkey)}/brand-grants`
  );
  return body.grants;
}

export async function createBrandGrant(
  teamRkey: string,
  grant: {
    brandDid: string;
    granteeType: GrantGranteeType;
    grantee: string;
    capabilities: BrandCapability[];
  }
): Promise<BrandGrantSummary> {
  return requestJSON<BrandGrantSummary>(
    `/v1/teams/${encodeURIComponent(teamRkey)}/brand-grants`,
    {
      method: "POST",
      body: JSON.stringify(grant),
    }
  );
}

export async function listBrands(teamRkey: string): Promise<BrandSummary[]> {
  const body = await requestJSON<{ brands: BrandSummary[] }>(
    `/v1/teams/${encodeURIComponent(teamRkey)}/brands`
  );
  return body.brands;
}

export async function designateBrand(
  teamRkey: string,
  brandDid: string
): Promise<BrandSummary> {
  return requestJSON<BrandSummary>(`/v1/teams/${encodeURIComponent(teamRkey)}/brands`, {
    method: "POST",
    body: JSON.stringify({ brandDid, status: "active" }),
  });
}

export async function getBrandProfile(did: string): Promise<BrandProfile> {
  return requestJSON<BrandProfile>(`/v1/brands/${didPath(did)}/profile`);
}

export async function updateBrandProfile(
  did: string,
  profile: Pick<BrandProfile, "displayName" | "description" | "avatar">
): Promise<BrandProfile> {
  return requestJSON<BrandProfile>(`/v1/brands/${didPath(did)}/profile`, {
    method: "PATCH",
    body: JSON.stringify(profile),
  });
}

export async function listAccountSchedules(
  did: string
): Promise<ScheduledPostSummary[]> {
  const body = await requestJSON<{ records: ScheduledPostSummary[] }>(
    `/v1/accounts/${didPath(did)}/schedules`
  );
  return body.records;
}

export async function listAuditEvents(did: string): Promise<AuditEvent[]> {
  const body = await requestJSON<{ events: AuditEvent[] }>(
    `/v1/accounts/${didPath(did)}/audit`
  );
  return body.events;
}

export async function recordScheduleView(did: string, rkey: string): Promise<void> {
  await requestJSON<{ ok: boolean }>(
    `/v1/accounts/${didPath(did)}/schedules/${encodeURIComponent(rkey)}/view`,
    { method: "POST" }
  );
}

export async function createSchedule(
  draft: ComposerDraft,
  did?: string,
  status?: ScheduleStatus
): Promise<ScheduledPostSummary> {
  const record = buildScheduleRecord(draft);
  if (status) record.status = status;
  const path = did
    ? `/v1/accounts/${didPath(did)}/schedules`
    : "/v1/schedules";
  return requestJSON<ScheduledPostSummary>(path, {
    method: "POST",
    body: JSON.stringify({ record }),
  });
}

export async function updateSchedule(
  rkey: string,
  draft: ComposerDraft,
  did?: string,
  status?: ScheduleStatus
): Promise<ScheduledPostSummary> {
  const record = buildScheduleRecord(draft);
  if (status) record.status = status;
  const path = did
    ? `/v1/accounts/${didPath(did)}/schedules/${encodeURIComponent(rkey)}`
    : `/v1/schedules/${encodeURIComponent(rkey)}`;
  return requestJSON<ScheduledPostSummary>(path, {
    method: "PATCH",
    body: JSON.stringify({ record }),
  });
}

export async function deleteSchedule(rkey: string): Promise<void> {
  await requestJSON<{ ok: boolean }>(`/v1/schedules/${encodeURIComponent(rkey)}`, {
    method: "DELETE",
  });
}

export async function cancelSchedule(
  did: string,
  rkey: string
): Promise<ScheduledPostSummary> {
  return requestJSON<ScheduledPostSummary>(
    `/v1/accounts/${didPath(did)}/schedules/${encodeURIComponent(rkey)}/cancel`,
    { method: "POST" }
  );
}

export async function retrySchedule(
  did: string,
  rkey: string
): Promise<ScheduledPostSummary> {
  return requestJSON<ScheduledPostSummary>(
    `/v1/accounts/${didPath(did)}/schedules/${encodeURIComponent(rkey)}/retry`,
    { method: "POST" }
  );
}

export async function duplicateSchedule(
  did: string,
  rkey: string
): Promise<ScheduledPostSummary> {
  return requestJSON<ScheduledPostSummary>(
    `/v1/accounts/${didPath(did)}/schedules/${encodeURIComponent(rkey)}/duplicate`,
    { method: "POST" }
  );
}

export async function publishNow(
  rkey: string,
  did?: string
): Promise<ScheduledPostSummary> {
  const path = did
    ? `/v1/accounts/${didPath(did)}/schedules/${encodeURIComponent(rkey)}/publish-now`
    : `/v1/schedules/${encodeURIComponent(rkey)}/publish-now`;
  return requestJSON<ScheduledPostSummary>(
    path,
    {
      method: "POST",
    }
  );
}
