import { describe, expect, it } from "bun:test";

import {
  buildScheduleRecord,
  countGraphemes,
  validateComposerDraft,
} from "@/lib/editor";

describe("composer validation", () => {
  it("requires a future scheduled time", () => {
    const issues = validateComposerDraft(
      {
        mode: "post",
        scheduledFor: "2020-01-01T10:00",
        posts: [{ text: "hello" }],
      },
      new Date("2026-01-01T10:00:00Z")
    );

    expect(issues.some((issue) => issue.field === "scheduledFor")).toBe(true);
  });

  it("requires alt text on images", () => {
    const issues = validateComposerDraft(
      {
        mode: "post",
        scheduledFor: "2026-01-01T11:00",
        posts: [
          {
            text: "photo later",
            embed: {
              images: [{ id: "1", alt: " ", previewUrl: "/icon.png" }],
            },
          },
        ],
      },
      new Date("2026-01-01T10:00:00Z")
    );

    expect(issues.map((issue) => issue.field)).toContain("posts.0.images.1.alt");
  });

  it("counts graphemes for emoji sequences", () => {
    expect(countGraphemes("Skej 🚀")).toBe(6);
  });
});

describe("schedule records", () => {
  it("builds an at.skej.schedule record", () => {
    const record = buildScheduleRecord(
      {
        mode: "post",
        scheduledFor: "2026-01-01T11:00",
        posts: [{ text: "  hello pds  ", langs: ["en"] }],
        contentWarning: "warn",
      },
      new Date("2026-01-01T10:00:00Z")
    );

    expect(record.$type).toBe("at.skej.schedule");
    expect(record.status).toBe("scheduled");
    expect(record.posts[0]?.text).toBe("hello pds");
    expect(record.posts[0]?.labels).toContain("warn");
  });
});

