import { describe, expect, it } from "bun:test";

import corpus from "../../../../test-fixtures/social-markdown.json";
import {
  applySocialMarkdownCommand,
  compileSocialMarkdown,
  projectMarkdownPost,
  projectionSegments,
} from "@/lib/socialMarkdown";

function compactFacets(facets: ReturnType<typeof compileSocialMarkdown>["facets"]) {
  return facets.map((facet) => {
    const feature = facet.features[0];
    if (feature?.$type === "app.bsky.richtext.facet#link") {
      return {
        byteStart: facet.index.byteStart,
        byteEnd: facet.index.byteEnd,
        type: "link",
        value: feature.uri,
      };
    }
    if (feature?.$type === "app.bsky.richtext.facet#tag") {
      return {
        byteStart: facet.index.byteStart,
        byteEnd: facet.index.byteEnd,
        type: "tag",
        value: feature.tag,
      };
    }
    throw new Error("Unexpected fixture facet");
  });
}

describe("social Markdown shared fixtures", () => {
  for (const fixture of corpus.cases) {
    it(fixture.name, () => {
      const compilation = compileSocialMarkdown(fixture.source);
      expect(compilation.text).toBe(fixture.text);
      expect(compactFacets(compilation.facets)).toEqual(fixture.facets);
    });
  }
});

describe("social Markdown commands", () => {
  it("wraps and unwraps a selected range", () => {
    const wrapped = applySocialMarkdownCommand("hello", "bold", 0, 5);
    expect(wrapped).toEqual({
      text: "**hello**",
      selectionStart: 2,
      selectionEnd: 7,
    });
    expect(
      applySocialMarkdownCommand(
        wrapped.text,
        "bold",
        wrapped.selectionStart,
        wrapped.selectionEnd
      )
    ).toEqual({ text: "hello", selectionStart: 0, selectionEnd: 5 });
  });

  it("wraps and unwraps selected lines as a fenced code block", () => {
    const wrapped = applySocialMarkdownCommand("let x = 1;", "code-block", 0, 10);
    expect(wrapped).toEqual({
      text: "```\nlet x = 1;\n```",
      selectionStart: 4,
      selectionEnd: 14,
    });
    expect(
      applySocialMarkdownCommand(
        wrapped.text,
        "code-block",
        wrapped.selectionStart,
        wrapped.selectionEnd
      )
    ).toEqual({
      text: "let x = 1;",
      selectionStart: 0,
      selectionEnd: 10,
    });
  });

  it("prefixes each selected list line and toggles the list off", () => {
    const listed = applySocialMarkdownCommand("one\ntwo", "unordered-list", 0, 7);
    expect(listed.text).toBe("- one\n- two");
    expect(
      applySocialMarkdownCommand(
        listed.text,
        "unordered-list",
        listed.selectionStart,
        listed.selectionEnd
      ).text
    ).toBe("one\ntwo");
  });

  it("inserts a selected label, keeps a safe scheme, and selects the hostname", () => {
    expect(applySocialMarkdownCommand("Read docs", "link", 5, 9)).toEqual({
      text: "Read [docs](https://example.com)",
      selectionStart: 20,
      selectionEnd: 31,
    });
  });

  it("compiles the result of replacing the selected hostname into hypertext", () => {
    const command = applySocialMarkdownCommand("Read docs", "link", 5, 9);
    const source =
      command.text.slice(0, command.selectionStart) +
      "skej.at" +
      command.text.slice(command.selectionEnd);

    expect(compileSocialMarkdown(source)).toEqual({
      text: "Read docs",
      facets: [
        {
          index: { byteStart: 5, byteEnd: 9 },
          features: [
            {
              $type: "app.bsky.richtext.facet#link",
              uri: "https://skej.at",
            },
          ],
        },
      ],
    });
  });
});

describe("post projection compatibility", () => {
  it("keeps legacy literal Markdown and facets unchanged", () => {
    const legacy = {
      text: "Legacy **literal** https://example.com",
      facets: [
        {
          index: { byteStart: 19, byteEnd: 38 },
          features: [
            {
              $type: "app.bsky.richtext.facet#link" as const,
              uri: "https://example.com",
            },
          ],
        },
      ],
    };
    expect(projectMarkdownPost(legacy)).toEqual(legacy);
  });

  it("splits UTF-8 facets into clickable preview segments", () => {
    const projected = compileSocialMarkdown("👋 [Skej](https://skej.at)");
    expect(projectionSegments(projected)).toEqual([
      { text: "👋 " },
      { text: "Skej", uri: "https://skej.at" },
    ]);
  });
});
