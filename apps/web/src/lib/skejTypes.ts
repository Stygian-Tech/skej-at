export const SKEJ_SCHEDULE_COLLECTION = "at.skej.schedule" as const;

export type ScheduleStatus =
  | "scheduled"
  | "publishing"
  | "published"
  | "failed"
  | "cancelled";

export type ComposerMode = "post" | "reply" | "quote";

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

export interface ExternalDraft {
  uri: string;
  title?: string;
  description?: string;
  thumb?: string;
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

export interface PostPlan {
  text: string;
  facets?: RichFacet[];
  reply?: ReplyDraft;
  embed?: {
    images?: ImageDraft[];
    external?: ExternalDraft;
    record?: QuoteDraft;
  };
  langs?: string[];
  labels?: string[];
  tags?: string[];
}

export interface SkejScheduleRecord {
  $type: typeof SKEJ_SCHEDULE_COLLECTION;
  scheduledFor: string;
  createdAt: string;
  updatedAt: string;
  status: ScheduleStatus;
  posts: PostPlan[];
}

export interface ScheduledPostSummary {
  rkey: string;
  did: string;
  scheduledFor: string;
  status: ScheduleStatus;
  record: SkejScheduleRecord;
  attempts: number;
  lastError?: string;
  publishedUri?: string;
  publishedCid?: string;
}

export interface Viewer {
  did: string;
  handle?: string;
  displayName?: string;
  avatar?: string;
}
