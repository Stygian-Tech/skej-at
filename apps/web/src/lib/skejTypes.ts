export const SKEJ_SCHEDULE_COLLECTION = "at.skej.schedule" as const;

export type ScheduleStatus =
  | "draft"
  | "scheduled"
  | "blocked"
  | "publishing"
  | "published"
  | "failed"
  | "canceled";

export type TimezonePolicy = "absolute_utc" | "account_local" | "user_local";

export type ScheduleErrorCode =
  | "transient_network"
  | "rate_limited"
  | "auth_invalid"
  | "record_invalid"
  | "parent_missing"
  | "parent_unavailable"
  | "unknown";

export interface ScheduleError {
  code: ScheduleErrorCode;
  message: string;
  classification: ScheduleErrorCode;
  retryAfter?: string;
}

export interface RetryState {
  attemptCount: number;
  lastAttemptAt?: string;
  nextAttemptAt?: string;
  maxAttempts: number;
}

export interface ScheduleDependency {
  dependsOnScheduleUri: string;
  parentPublishedUri?: string;
  parentPublishedCid?: string;
  relationship?: "after" | "reply" | "quote";
}

export type ComposerMode = "post" | "reply" | "quote";

export interface MentionActor {
  handle: string;
  did: string;
  displayName?: string;
  avatar?: string;
}

export interface ResolvedMention {
  handle: string;
  did: string;
}

export interface RichFacet {
  index: {
    byteStart: number;
    byteEnd: number;
  };
  features: Array<
    | {
        $type: "app.bsky.richtext.facet#link";
        uri: string;
      }
    | {
        $type: "app.bsky.richtext.facet#mention";
        did: string;
      }
    | {
        $type: "app.bsky.richtext.facet#tag";
        tag: string;
      }
  >;
}

export interface ImageDraft {
  id: string;
  alt: string;
  previewUrl: string;
}

export interface ATProtoBlobRef {
  $type: "blob";
  ref: {
    $link: string;
  };
  mimeType: string;
  size: number;
}

export interface ExternalDraft {
  uri: string;
  title?: string;
  description?: string;
  thumb?: ATProtoBlobRef;
}

export interface ExternalEmbedContent {
  uri: string;
  title: string;
  description: string;
  thumb?: ATProtoBlobRef;
}

export interface ExternalEmbed {
  $type: "app.bsky.embed.external";
  external: ExternalEmbedContent;
}

export interface QuoteDraft {
  uri: string;
  cid: string;
}

export interface ReplyDraft {
  root: {
    uri: string;
    cid: string;
  };
  parent: {
    uri: string;
    cid: string;
  };
}

export interface PostSource {
  format: "markdown";
  text: string;
  mentions?: ResolvedMention[];
}

export interface PostPlan {
  source?: PostSource;
  text: string;
  facets?: RichFacet[];
  publishRkey?: string;
  reply?: ReplyDraft;
  embed?: {
    $type?:
      | "app.bsky.embed.external"
      | "app.bsky.embed.images"
      | "app.bsky.embed.record";
    images?: ImageDraft[];
    external?: ExternalDraft;
    record?: QuoteDraft;
  };
  langs?: string[];
  labels?: string[];
  tags?: string[];
}

export interface PublishedPostReference {
  rkey: string;
  uri: string;
  cid: string;
}

export interface LinkPreviewRequest {
  url: string;
}

export interface SkejScheduleRecord {
  $type: typeof SKEJ_SCHEDULE_COLLECTION;
  scheduledAt: string;
  title?: string;
  teamUri?: string;
  createdByDid?: string;
  approvedByDid?: string;
  approvedAt?: string;
  timezonePolicy: TimezonePolicy;
  userTimezone?: string;
  createdAt: string;
  updatedAt: string;
  status: ScheduleStatus;
  recordType: string;
  shadowRecord?: unknown;
  publishRkey: string;
  calendarEventUri?: string;
  calendarEventCid?: string;
  publishedUri?: string;
  publishedCid?: string;
  publishedPosts?: PublishedPostReference[];
  retry: RetryState;
  lastError?: ScheduleError;
  dependency?: ScheduleDependency;
  posts: PostPlan[];
  scheduledFor?: string;
}

export interface ScheduledPostSummary {
  rkey: string;
  did: string;
  scheduleUri: string;
  scheduledAt: string;
  scheduledFor?: string;
  status: ScheduleStatus;
  record: SkejScheduleRecord;
  attempts: number;
  lastError?: ScheduleError;
  nextAttemptAt?: string;
  publishedUri?: string;
  publishedCid?: string;
}

export interface CommunityCalendarEventRecord {
  $type: "community.lexicon.calendar.event";
  name: string;
  uris?: Array<{ uri: string; name?: string }>;
  startsAt?: string;
  endsAt?: string;
  status?:
    | "community.lexicon.calendar.event#planned"
    | "community.lexicon.calendar.event#scheduled"
    | "community.lexicon.calendar.event#rescheduled"
    | "community.lexicon.calendar.event#postponed"
    | "community.lexicon.calendar.event#cancelled";
  mode?: string;
  createdAt: string;
}

export interface ManagedAccount {
  did: string;
  handle?: string;
  displayName?: string;
  avatar?: string;
  pdsEndpoint?: string;
  status: "active" | "needs_reauth" | "disabled";
  isDefault: boolean;
}

export type TeamStatus = "active" | "archived";
export type TeamRole = "admin" | "user";
export type MembershipStatus = "active" | "disabled";
export type BrandCapability = "create" | "approve" | "manage" | "viewAnalytics";
export type GrantGranteeType = "member" | "group";
export type TeamGroupStatus = "active" | "archived";
export type BrandGrantStatus = "active" | "revoked";

export interface SkejTeamRecord {
  $type: "at.skej.team";
  ownerAdminDid: string;
  title: string;
  status: TeamStatus;
  createdAt: string;
  updatedAt: string;
}

export interface TeamMemberRecord {
  $type: "at.skej.team.member";
  teamUri: string;
  memberDid: string;
  role: TeamRole;
  status: MembershipStatus;
  groupUris?: string[];
  createdAt: string;
  updatedAt: string;
}

export interface TeamGroupRecord {
  $type: "at.skej.team.group";
  teamUri: string;
  name: string;
  memberDids?: string[];
  brandGrantUris?: string[];
  status: TeamGroupStatus;
  createdAt: string;
  updatedAt: string;
}

export interface BrandGrantRecord {
  $type: "at.skej.team.brandGrant";
  teamUri: string;
  brandDid: string;
  granteeType: GrantGranteeType;
  grantee: string;
  capabilities: BrandCapability[];
  status: BrandGrantStatus;
  createdAt: string;
  updatedAt: string;
}

export interface SkejBrandRecord {
  $type: "at.skej.brand";
  teamUri: string;
  ownerAdminDid: string;
  brandDid: string;
  status: ManagedAccount["status"];
  createdAt: string;
  updatedAt: string;
}

export interface TeamSummary {
  rkey: string;
  uri: string;
  record: SkejTeamRecord;
}

export interface TeamInvite {
  id: string;
  token: string;
  teamUri: string;
  teamTitle: string;
  ownerDid: string;
  invitedHandle?: string;
  invitedDid?: string;
  role: TeamRole;
  status: "pending" | "accepted" | "revoked" | "expired";
  inviterDid: string;
  acceptedDid?: string;
  createdAt: string;
  expiresAt: string;
  updatedAt: string;
}

export interface ProEntitlement {
  scope: "actor" | "team";
  subject: string;
  status: "active" | "revoked";
  source: string;
  grantedByDid?: string;
  expiresAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface TeamMemberSummary {
  rkey: string;
  uri: string;
  record: TeamMemberRecord;
}

export interface TeamGroupSummary {
  rkey: string;
  uri: string;
  record: TeamGroupRecord;
}

export interface BrandGrantSummary {
  rkey: string;
  uri: string;
  record: BrandGrantRecord;
}

export interface BrandSummary {
  rkey: string;
  uri: string;
  record: SkejBrandRecord;
}

export interface EffectiveBrandPermission {
  brandDid: string;
  capabilities: BrandCapability[];
}

export interface BrandProfile {
  did: string;
  handle?: string;
  displayName?: string;
  description?: string;
  avatar?: string;
}

export interface AuditEvent {
  id: string;
  did: string;
  scheduleRkey?: string;
  action: string;
  message: string;
  createdAt: string;
}

export interface Viewer {
  did: string;
  handle?: string;
  displayName?: string;
  avatar?: string;
  defaultAccountDid?: string;
  proFeaturesEnabled?: boolean;
}
