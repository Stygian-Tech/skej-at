import {
  ComposerMode,
  PostPlan,
  SKEJ_SCHEDULE_COLLECTION,
  SkejScheduleRecord,
} from "@/lib/skejTypes";

export const MAX_POST_GRAPHEMES = 300;

export interface ComposerDraft {
  mode: ComposerMode;
  posts: PostPlan[];
  scheduledFor: string;
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

export function normalizePost(plan: PostPlan): PostPlan {
  const text = plan.text.trim();
  return {
    ...plan,
    text,
    langs: plan.langs?.map((lang) => lang.trim()).filter(Boolean),
    labels: plan.labels?.map((label) => label.trim()).filter(Boolean),
    tags: plan.tags?.map((tag) => tag.trim()).filter(Boolean),
  };
}

export function validateComposerDraft(draft: ComposerDraft, now = new Date()): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const posts = draft.posts.map(normalizePost);

  if (posts.length === 0) {
    issues.push({ field: "posts", message: "Add at least one post." });
  }

  posts.forEach((post, index) => {
    if (!post.text) {
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
    const first = posts[0];
    if (!first?.reply) {
      issues.push({
        field: "reply",
        message: "Add the Bluesky post you want to reply to.",
      });
    }
  }

  if (draft.mode === "quote") {
    const first = posts[0];
    if (!first?.embed?.record) {
      issues.push({
        field: "quote",
        message: "Add the Bluesky post you want to quote.",
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
    const normalized = normalizePost(post);
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
  return {
    $type: SKEJ_SCHEDULE_COLLECTION,
    scheduledFor: new Date(draft.scheduledFor).toISOString(),
    createdAt: timestamp,
    updatedAt: timestamp,
    status: "scheduled",
    posts,
  };
}

export function localDatetimeValue(date: Date): string {
  const offset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - offset * 60_000);
  return local.toISOString().slice(0, 16);
}
