import { ComposerDraft, buildScheduleRecord } from "@/lib/editor";
import {
  AuditEvent,
  BrandCapability,
  BrandGrantSummary,
  BrandProfile,
  BrandSummary,
  GrantGranteeType,
  ExternalEmbed,
  ManagedAccount,
  ScheduleStatus,
  ScheduledPostSummary,
  TeamGroupSummary,
  TeamMemberSummary,
  TeamRole,
  TeamSummary,
  Viewer,
} from "@/lib/skejTypes";

const XRPC = {
  getSession: "at.skej.actor.getSession",
  logout: "at.skej.auth.logout",
  listAccounts: "at.skej.account.list",
  listTeams: "at.skej.team.list",
  createTeam: "at.skej.team.create",
  listMembers: "at.skej.team.listMembers",
  putMember: "at.skej.team.putMember",
  listGroups: "at.skej.team.listGroups",
  putGroup: "at.skej.team.putGroup",
  listBrandGrants: "at.skej.team.listBrandGrants",
  putBrandGrant: "at.skej.team.putBrandGrant",
  listBrands: "at.skej.team.listBrands",
  putBrand: "at.skej.team.putBrand",
  getBrandProfile: "at.skej.brand.getProfile",
  updateBrandProfile: "at.skej.brand.updateProfile",
  listSchedules: "at.skej.schedule.list",
  createSchedule: "at.skej.schedule.create",
  updateSchedule: "at.skej.schedule.update",
  cancelSchedule: "at.skej.schedule.cancel",
  retrySchedule: "at.skej.schedule.retry",
  duplicateSchedule: "at.skej.schedule.duplicate",
  publishNow: "at.skej.schedule.publishNow",
  recordView: "at.skej.schedule.recordView",
  createLinkPreview: "at.skej.preview.createLink",
  listAuditEvents: "at.skej.audit.list",
} as const;

function xrpcQuery(nsid: string, parameters: Record<string, string | undefined> = {}): string {
  const query = new URLSearchParams();
  for (const [name, value] of Object.entries(parameters)) {
    if (value !== undefined) query.set(name, value);
  }
  const suffix = query.size > 0 ? `?${query.toString()}` : "";
  return `/xrpc/${nsid}${suffix}`;
}

function xrpcProcedure<T>(nsid: string, input: unknown, signal?: AbortSignal): Promise<T> {
  return requestJSON<T>(`/xrpc/${nsid}`, {
    method: "POST",
    body: JSON.stringify(input),
    signal,
  });
}

/** Carries the API's error code so callers can branch on it, not on copy. */
export class SkejApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(message: string, code: string, status: number) {
    super(message);
    this.name = "SkejApiError";
    this.code = code;
    this.status = status;
  }
}

export function isReauthRequired(error: unknown): boolean {
  return error instanceof SkejApiError && error.code === "account_needs_reauth";
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
    throw new SkejApiError(
      body?.message ?? body?.error ?? "Skej could not load this right now. Try again soon.",
      body?.error ?? "unknown_error",
      response.status
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
  return requestJSON<Viewer>(xrpcQuery(XRPC.getSession));
}

export async function logout(): Promise<void> {
  await xrpcProcedure<{ ok: boolean }>(XRPC.logout, {});
}

export async function listSchedules(): Promise<ScheduledPostSummary[]> {
  const body = await requestJSON<{ records: ScheduledPostSummary[] }>(
    xrpcQuery(XRPC.listSchedules)
  );
  return body.records;
}

export async function listAccounts(): Promise<ManagedAccount[]> {
  const body = await requestJSON<{ accounts: ManagedAccount[] }>(
    xrpcQuery(XRPC.listAccounts)
  );
  return body.accounts;
}

export async function listTeams(): Promise<TeamSummary[]> {
  const body = await requestJSON<{ teams: TeamSummary[] }>(xrpcQuery(XRPC.listTeams));
  return body.teams;
}

export async function createTeam(title: string): Promise<TeamSummary> {
  return xrpcProcedure<TeamSummary>(XRPC.createTeam, { title });
}

export async function listTeamMembers(teamRkey: string): Promise<TeamMemberSummary[]> {
  const body = await requestJSON<{ members: TeamMemberSummary[] }>(
    xrpcQuery(XRPC.listMembers, { teamRkey })
  );
  return body.members;
}

export async function addTeamMember(
  teamRkey: string,
  memberDid: string,
  role: TeamRole
): Promise<TeamMemberSummary> {
  return xrpcProcedure<TeamMemberSummary>(XRPC.putMember, {
    teamRkey,
    memberDid,
    role,
    status: "active",
    groupUris: [],
  });
}

export async function listTeamGroups(teamRkey: string): Promise<TeamGroupSummary[]> {
  const body = await requestJSON<{ groups: TeamGroupSummary[] }>(
    xrpcQuery(XRPC.listGroups, { teamRkey })
  );
  return body.groups;
}

export async function createTeamGroup(
  teamRkey: string,
  name: string,
  memberDids: string[] = []
): Promise<TeamGroupSummary> {
  return xrpcProcedure<TeamGroupSummary>(XRPC.putGroup, {
    teamRkey,
    name,
    memberDids,
    brandGrantUris: [],
  });
}

export async function listBrandGrants(teamRkey: string): Promise<BrandGrantSummary[]> {
  const body = await requestJSON<{ grants: BrandGrantSummary[] }>(
    xrpcQuery(XRPC.listBrandGrants, { teamRkey })
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
  return xrpcProcedure<BrandGrantSummary>(XRPC.putBrandGrant, { teamRkey, ...grant });
}

export async function listBrands(teamRkey: string): Promise<BrandSummary[]> {
  const body = await requestJSON<{ brands: BrandSummary[] }>(
    xrpcQuery(XRPC.listBrands, { teamRkey })
  );
  return body.brands;
}

export async function designateBrand(
  teamRkey: string,
  brandDid: string
): Promise<BrandSummary> {
  return xrpcProcedure<BrandSummary>(XRPC.putBrand, {
    teamRkey,
    brandDid,
    status: "active",
  });
}

export async function getBrandProfile(did: string): Promise<BrandProfile> {
  return requestJSON<BrandProfile>(xrpcQuery(XRPC.getBrandProfile, { did }));
}

export async function updateBrandProfile(
  did: string,
  profile: Pick<BrandProfile, "displayName" | "description" | "avatar">
): Promise<BrandProfile> {
  return xrpcProcedure<BrandProfile>(XRPC.updateBrandProfile, { did, ...profile });
}

export async function listAccountSchedules(
  did: string
): Promise<ScheduledPostSummary[]> {
  const body = await requestJSON<{ records: ScheduledPostSummary[] }>(
    xrpcQuery(XRPC.listSchedules, { accountDid: did })
  );
  return body.records;
}

export async function listAuditEvents(did: string): Promise<AuditEvent[]> {
  const body = await requestJSON<{ events: AuditEvent[] }>(
    xrpcQuery(XRPC.listAuditEvents, { accountDid: did })
  );
  return body.events;
}

export async function recordScheduleView(did: string, rkey: string): Promise<void> {
  await xrpcProcedure<{ ok: boolean }>(XRPC.recordView, { accountDid: did, rkey });
}

export async function hydrateLinkPreview(
  did: string,
  url: string,
  signal?: AbortSignal
): Promise<ExternalEmbed> {
  return xrpcProcedure<ExternalEmbed>(
    XRPC.createLinkPreview,
    { accountDid: did, url },
    signal
  );
}

export async function createSchedule(
  draft: ComposerDraft,
  did?: string,
  status?: ScheduleStatus
): Promise<ScheduledPostSummary> {
  const record = buildScheduleRecord(draft);
  if (status) record.status = status;
  return xrpcProcedure<ScheduledPostSummary>(XRPC.createSchedule, {
    accountDid: did,
    record,
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
  return xrpcProcedure<ScheduledPostSummary>(XRPC.updateSchedule, {
    accountDid: did,
    rkey,
    record,
  });
}

export async function deleteSchedule(rkey: string): Promise<void> {
  await xrpcProcedure<ScheduledPostSummary>(XRPC.cancelSchedule, { rkey });
}

export async function cancelSchedule(
  did: string,
  rkey: string
): Promise<ScheduledPostSummary> {
  return xrpcProcedure<ScheduledPostSummary>(XRPC.cancelSchedule, {
    accountDid: did,
    rkey,
  });
}

export async function retrySchedule(
  did: string,
  rkey: string
): Promise<ScheduledPostSummary> {
  return xrpcProcedure<ScheduledPostSummary>(XRPC.retrySchedule, {
    accountDid: did,
    rkey,
  });
}

export async function duplicateSchedule(
  did: string,
  rkey: string
): Promise<ScheduledPostSummary> {
  return xrpcProcedure<ScheduledPostSummary>(XRPC.duplicateSchedule, {
    accountDid: did,
    rkey,
  });
}

export async function publishNow(
  rkey: string,
  did?: string
): Promise<ScheduledPostSummary> {
  return xrpcProcedure<ScheduledPostSummary>(XRPC.publishNow, {
    accountDid: did,
    rkey,
  });
}
