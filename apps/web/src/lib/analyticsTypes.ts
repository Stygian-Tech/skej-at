export type EngagementBucket = "day" | "week";
export type EngagementMetric =
  | "total"
  | "likes"
  | "reposts"
  | "replies"
  | "quotes"
  | "bookmarks";
export type EngagementDataStatus = "live" | "stale" | "partial";

export interface EngagementTotals {
  likes: number;
  reposts: number;
  replies: number;
  quotes: number;
  bookmarks: number;
  /** Likes + reposts + replies + quotes. Bookmarks are intentionally separate. */
  total: number;
}

export interface EngagementPoint extends EngagementTotals {
  bucketStart: string;
}

export interface EngagementAccountIdentity {
  did: string;
  handle?: string;
  displayName?: string;
  avatar?: string;
}

export interface EngagementAccountSeries {
  account: EngagementAccountIdentity;
  trackedPostCount: number;
  unavailablePostCount: number;
  lifetime: EngagementTotals;
  period: EngagementTotals;
  points: EngagementPoint[];
}

export interface GetEngagementOutput {
  generatedAt: string;
  coverageStartedAt?: string;
  lastCollectedAt?: string;
  status: EngagementDataStatus;
  accounts: EngagementAccountSeries[];
}

export interface GetEngagementParameters {
  from: string;
  to: string;
  bucket: EngagementBucket;
  timezone: string;
  accountDids?: string[];
}
