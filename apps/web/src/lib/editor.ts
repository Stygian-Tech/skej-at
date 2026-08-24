import {
  ComposerMode,
  PostPlan,
  SKEJ_SCHEDULE_COLLECTION,
  SkejScheduleRecord,
} from "@/lib/skejTypes";
import { projectMarkdownPost } from "@/lib/socialMarkdown";

export const MAX_POST_GRAPHEMES = 300;
export const MAX_SCHEDULE_TITLE_GRAPHEMES = 120;
const HTTP_URL_PATTERN = /https?:\/\/[^\s<>"']+/giu;
const SIMPLE_TRAILING_PUNCTUATION = /[.,!?;:]+$/u;

export interface ComposerDraft {
  mode: ComposerMode;
  title?: string;
  posts: PostPlan[];
  scheduledFor: string;
  timezone?: string;
  dependencyScheduleUri?: string;
  contentWarning?: string;
}

export interface ValidationIssue {
  field: string;
  message: string;
}

export function countGraphemes(text: string): number {
  if (typeof Intl !== "undefined" && "Segmenter" in Intl) {
    const Segmenter = Intl.Segmenter;
    const segmenter = new Segmenter("en", { granularity: "grapheme" });
    return Array.from(segmenter.segment(text)).length;
  }
  return Array.from(text).length;
}

export function firstHTTPURL(text: string): string | undefined {
  HTTP_URL_PATTERN.lastIndex = 0;
  const match = HTTP_URL_PATTERN.exec(text);
  if (!match) return undefined;

  let candidate = match[0].replace(SIMPLE_TRAILING_PUNCTUATION, "");
  const pairs: Array<[string, string]> = [
    ["(", ")"],
    ["[", "]"],
    ["{", "}"],
  ];
  let changed = true;
  while (changed) {
    changed = false;
    for (const [open, close] of pairs) {
      if (
        candidate.endsWith(close) &&
        candidate.split(close).length > candidate.split(open).length
      ) {
        candidate = candidate.slice(0, -1);
        changed = true;
      }
    }
  }

  try {
    const url = new URL(candidate);
    return url.protocol === "http:" || url.protocol === "https:"
      ? candidate
      : undefined;
  } catch {
    return undefined;
  }
}

export function normalizePost(plan: PostPlan): PostPlan {
  const projected = projectMarkdownPost(plan);
  return {
    ...projected,
    text: plan.source?.format === "markdown" ? projected.text : projected.text.trim(),
    langs: plan.langs?.map((lang) => lang.trim()).filter(Boolean),
    labels: plan.labels?.map((label) => label.trim()).filter(Boolean),
    tags: plan.tags?.map((tag) => tag.trim()).filter(Boolean),
  };
}

export function firstPostLinkURL(plan: PostPlan): string | undefined {
  const projected = projectMarkdownPost(plan);
  for (const facet of projected.facets ?? []) {
    for (const feature of facet.features) {
      if (feature.$type === "app.bsky.richtext.facet#link") return feature.uri;
    }
  }
  return firstHTTPURL(projected.text);
}

export function validateComposerDraft(draft: ComposerDraft, now = new Date()): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const posts = draft.posts.map(normalizePost);
  const title = draft.title?.trim() ?? "";

  if (title && countGraphemes(title) > MAX_SCHEDULE_TITLE_GRAPHEMES) {
    issues.push({
      field: "title",
      message: `Title is over ${MAX_SCHEDULE_TITLE_GRAPHEMES} characters.`,
    });
  }

  if (posts.length === 0) {
    issues.push({ field: "posts", message: "Add at least one post." });
  }

  posts.forEach((post, index) => {
    if (!post.text.trim()) {
      issues.push({
        field: `posts.${index}.text`,
        message: "Post text is required.",
      });
    }
    if (countGraphemes(post.text) > MAX_POST_GRAPHEMES) {
      issues.push({
        field: `posts.${index}.text`,
        message: `Post ${index + 1} is over ${MAX_POST_GRAPHEMES} characters.`,
      });
    }
    for (const image of post.embed?.images ?? []) {
      if (!image.alt.trim()) {
        issues.push({
          field: `posts.${index}.images.${image.id}.alt`,
          message: "Every image needs alt text.",
        });
      }
    }
  });

  const scheduled = new Date(draft.scheduledFor);
  if (Number.isNaN(scheduled.valueOf())) {
    issues.push({ field: "scheduledFor", message: "Choose a valid scheduled time." });
  } else if (scheduled.getTime() <= now.getTime() + 30_000) {
    issues.push({
      field: "scheduledFor",
      message: "Schedule at least 30 seconds in the future.",
    });
  }

  if (draft.mode === "reply") {
    if (!draft.dependencyScheduleUri) {
      issues.push({
        field: "reply",
        message: "Choose a Skej-managed post to reply to.",
      });
    }
  }

  if (draft.mode === "quote") {
    if (!draft.dependencyScheduleUri) {
      issues.push({
        field: "quote",
        message: "Choose a Skej-managed post to quote.",
      });
    }
  }

  return issues;
}

export function buildScheduleRecord(
  draft: ComposerDraft,
  now = new Date()
): SkejScheduleRecord {
  const issues = validateComposerDraft(draft, now);
  if (issues.length > 0) {
    throw new Error(issues[0]?.message ?? "Invalid schedule.");
  }

  const posts = draft.posts.map((post) => {
    const normalized = {
      ...normalizePost(post),
      publishRkey: post.publishRkey ?? generateTID(now),
    };
    if (draft.contentWarning?.trim()) {
      return {
        ...normalized,
        labels: Array.from(
          new Set([...(normalized.labels ?? []), draft.contentWarning.trim()])
        ),
      };
    }
    return normalized;
  });

  const timestamp = now.toISOString();
  const scheduledAt = new Date(draft.scheduledFor).toISOString();
  const publishRkey = posts[0]?.publishRkey ?? generateTID(now);
  return {
    $type: SKEJ_SCHEDULE_COLLECTION,
    scheduledAt,
    title: draft.title?.trim() || undefined,
    timezonePolicy: "user_local",
    userTimezone:
      draft.timezone ??
      Intl.DateTimeFormat().resolvedOptions().timeZone ??
      "UTC",
    createdAt: timestamp,
    updatedAt: timestamp,
    status: "scheduled",
    recordType: "app.bsky.feed.post",
    publishRkey,
    retry: {
      attemptCount: 0,
      maxAttempts: 8,
    },
    dependency: draft.dependencyScheduleUri
      ? {
          dependsOnScheduleUri: draft.dependencyScheduleUri,
          relationship: draft.mode === "post" ? "after" : draft.mode,
        }
      : undefined,
    posts,
  };
}

export function localDatetimeValue(date: Date): string {
  const offset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - offset * 60_000);
  return local.toISOString().slice(0, 16);
}

const TID_ALPHABET = "234567abcdefghijklmnopqrstuvwxyz";
let lastTIDValue = BigInt(0);

export function generateTID(date = new Date()): string {
  const micros = BigInt(date.getTime()) * BigInt(1_000);
  const clockID = BigInt(Math.floor(Math.random() * 1_024));
  const candidate = (micros << BigInt(10)) | clockID;
  let value = candidate > lastTIDValue ? candidate : lastTIDValue + BigInt(1);
  lastTIDValue = value;

  let encoded = "";
  for (let index = 0; index < 13; index += 1) {
    encoded = TID_ALPHABET[Number(value & BigInt(31))] + encoded;
    value >>= BigInt(5);
  }
  return encoded;
}
