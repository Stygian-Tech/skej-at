import { describe, expect, test } from "bun:test";

import {
  LINK_PREVIEW_DEBOUNCE_MS,
  automaticLinkPreviewURL,
  canApplyAutomaticLinkPreview,
  shouldRemoveAutomaticLinkPreview,
} from "@/lib/linkPreview";
import type { PostPlan } from "@/lib/skejTypes";

describe("automatic link preview state", () => {
  test("uses the first eligible URL independently for each thread post", () => {
    const posts: PostPlan[] = [
      { text: "First https://one.example and https://later.example" },
      { text: "Second https://two.example" },
    ];

    expect(posts.map(automaticLinkPreviewURL)).toEqual([
      "https://one.example",
      "https://two.example",
    ]);
  });

  test("does not replace image or quote embeds", () => {
    expect(
      automaticLinkPreviewURL({
        text: "Image https://example.com",
        embed: {
          $type: "app.bsky.embed.images",
          images: [{ id: "draft", alt: "", previewUrl: "" }],
        },
      })
    ).toBeNull();
    expect(
      automaticLinkPreviewURL({
        text: "Quote https://example.com",
        embed: {
          $type: "app.bsky.embed.record",
          record: {
            uri: "at://did:plc:test/app.bsky.feed.post/abc",
            cid: "bafytest",
          },
        },
      })
    ).toBeNull();
  });

  test("rejects stale hydration responses after the URL changes", () => {
    expect(
      canApplyAutomaticLinkPreview(
        { text: "Now https://new.example" },
        "https://old.example"
      )
    ).toBeFalse();
    expect(
      canApplyAutomaticLinkPreview(
        { text: "Still https://same.example" },
        "https://same.example"
      )
    ).toBeTrue();
  });

  test("does not overwrite a manual external card with a stale response", () => {
    const post: PostPlan = {
      text: "Read https://example.com",
      embed: {
        $type: "app.bsky.embed.external",
        external: {
          uri: "https://manual.example",
          title: "Manual",
          description: "Keep this card",
        },
      },
    };

    expect(
      canApplyAutomaticLinkPreview(post, "https://example.com")
    ).toBeFalse();
    expect(
      canApplyAutomaticLinkPreview(
        {
          ...post,
          embed: {
            $type: "app.bsky.embed.external",
            external: {
              uri: "https://old-auto.example",
              title: "Old automatic card",
              description: "",
            },
          },
        },
        "https://example.com",
        "https://old-auto.example"
      )
    ).toBeTrue();
  });

  test("removes an automatic card when its source URL is removed", () => {
    expect(
      shouldRemoveAutomaticLinkPreview(
        {
          text: "The URL is gone",
          embed: {
            $type: "app.bsky.embed.external",
            external: {
              uri: "https://example.com",
              title: "Example",
              description: "",
            },
          },
        },
        "https://example.com"
      )
    ).toBeTrue();
  });

  test("uses a deliberate debounce window", () => {
    expect(LINK_PREVIEW_DEBOUNCE_MS).toBe(500);
  });
});
