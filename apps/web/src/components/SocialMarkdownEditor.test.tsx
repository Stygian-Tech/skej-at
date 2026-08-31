import { afterEach, beforeAll, describe, expect, it } from "bun:test";
import { Window } from "happy-dom";
import * as React from "react";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";

import { SocialMarkdownEditor } from "@/components/SocialMarkdownEditor";
import type { PostPlan } from "@/lib/skejTypes";

let container: HTMLDivElement;
let root: Root;

beforeAll(() => {
  const browser = new Window({ url: "https://skej.test/app" });
  Object.assign(globalThis, {
    window: browser,
    document: browser.document,
    navigator: browser.navigator,
    HTMLElement: browser.HTMLElement,
    HTMLTextAreaElement: browser.HTMLTextAreaElement,
    MouseEvent: browser.MouseEvent,
    KeyboardEvent: browser.KeyboardEvent,
    Event: browser.Event,
    requestAnimationFrame: (callback: FrameRequestCallback) => setTimeout(callback, 0),
    cancelAnimationFrame: clearTimeout,
    IS_REACT_ACT_ENVIRONMENT: true,
  });
});

afterEach(async () => {
  if (root) await act(async () => root.unmount());
  container?.remove();
});

async function render(element: React.ReactNode) {
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  await act(async () => root.render(element));
}

function click(element: Element) {
  element.dispatchEvent(new MouseEvent("click", { bubbles: true }));
}

function EditorPair() {
  const [posts, setPosts] = React.useState<PostPlan[]>([
    {
      source: { format: "markdown", text: "first post" },
      text: "first post",
      publishRkey: "first",
    },
    {
      source: { format: "markdown", text: "second post" },
      text: "second post",
      publishRkey: "second",
    },
  ]);
  return posts.map((post, index) => (
    <SocialMarkdownEditor
      index={index}
      key={post.publishRkey}
      onChange={(next) =>
        setPosts((current) =>
          current.map((entry, entryIndex) => (entryIndex === index ? next : entry))
        )
      }
      post={post}
    />
  ));
}

describe("SocialMarkdownEditor", () => {
  it("formats only the selected post as monospace and restores the selected text", async () => {
    await render(<EditorPair />);
    const textareas = Array.from(container.querySelectorAll("textarea"));
    textareas[0].setSelectionRange(0, 5);
    const firstToolbar = container.querySelectorAll('[role="toolbar"]')[0];
    if (!firstToolbar) throw new Error("Formatting toolbar was not rendered");
    const monospace = firstToolbar.querySelector('button[aria-label="Monospace"]');
    if (!monospace) throw new Error("Monospace button was not rendered");

    await act(async () => click(monospace));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(textareas[0].value).toBe("`first` post");
    expect(textareas[1].value).toBe("second post");
    expect(textareas[0].selectionStart).toBe(1);
    expect(textareas[0].selectionEnd).toBe(6);
  });

  it("supports keyboard shortcuts without affecting another post", async () => {
    await render(<EditorPair />);
    const textareas = Array.from(container.querySelectorAll("textarea"));
    textareas[1].setSelectionRange(0, 6);

    await act(async () => {
      textareas[1].dispatchEvent(
        new KeyboardEvent("keydown", { bubbles: true, ctrlKey: true, key: "i" })
      );
    });

    expect(textareas[0].value).toBe("first post");
    expect(textareas[1].value).toBe("*second* post");
  });

  it("renders the exact Bluesky projection with safe clickable links", async () => {
    const post: PostPlan = {
      source: {
        format: "markdown",
        text: "👋 [Open **Skej**](https://skej.at)",
      },
      text: "stale",
    };
    await render(
      <SocialMarkdownEditor index={0} onChange={() => undefined} post={post} />
    );

    const preview = container.querySelector('[id="post-1-bluesky-output"]');
    if (!preview) throw new Error("Inline Bluesky output was not rendered");
    const link = preview.querySelector("a");
    expect(preview.textContent).toBe("👋 Open Skej");
    expect(link?.textContent).toBe("Open Skej");
    expect(link?.getAttribute("href")).toBe("https://skej.at");
    expect(link?.getAttribute("rel")).toContain("noopener");
    expect(container.querySelector('[role="tablist"]')).toBeNull();
  });

  it("keeps the URL scheme when the Link toolbar command selects its hostname", async () => {
    await render(<EditorPair />);
    const textarea = container.querySelector("textarea");
    const linkButton = container.querySelector('button[aria-label="Link"]');
    if (!textarea || !linkButton) throw new Error("Link editor controls were not rendered");
    textarea.setSelectionRange(0, 5);

    await act(async () => click(linkButton));
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(textarea.value).toBe("[first](https://example.com) post");
    expect(textarea.value.slice(textarea.selectionStart, textarea.selectionEnd)).toBe(
      "example.com"
    );
  });

  it("shows only native links and limited-support code controls", async () => {
    await render(<EditorPair />);
    const toolbar = container.querySelector('[role="toolbar"]');
    const labels = Array.from(toolbar?.querySelectorAll("button") ?? []).map((button) =>
      button.getAttribute("aria-label")
    );

    expect(labels).toEqual(["Link", "Monospace", "Code block"]);
    expect(container.textContent).toContain(
      "Monospace and code blocks have limited client support."
    );
  });

  it("renders inline monospace and fenced code blocks in the Bluesky output", async () => {
    const post: PostPlan = {
      source: {
        format: "markdown",
        text: "Use `mono` here.\n```ts\nconst answer = 42;\n```",
      },
      text: "stale",
    };
    await render(
      <SocialMarkdownEditor index={0} onChange={() => undefined} post={post} />
    );

    const output = container.querySelector('[id="post-1-bluesky-output"]');
    const inlineCode = output?.querySelector(":scope > code");
    const block = output?.querySelector("pre code");
    expect(inlineCode?.textContent).toBe("mono");
    expect(block?.textContent).toBe("const answer = 42;");
  });

  it("keeps legacy literal Markdown until the author edits it", async () => {
    const legacy: PostPlan = { text: "Keep **literal**" };
    await render(
      <SocialMarkdownEditor index={0} onChange={() => undefined} post={legacy} />
    );
    expect(container.querySelector('[id="post-1-bluesky-output"]')?.textContent).toBe(
      "Keep **literal**"
    );
  });

  it("resolves an at-mention with the keyboard and previews exact native facets", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = (async () => ({
      ok: true,
      json: async () => ({
        actors: [
          {
            handle: "alice.test",
            did: "did:plc:alice",
            displayName: "Alice",
          },
        ],
      }),
    })) as unknown as typeof fetch;
    try {
      await render(<EditorPair />);
      const textarea = container.querySelector("textarea");
      if (!textarea) throw new Error("Editor was not rendered");
      await act(async () => {
        const valueSetter = Object.getOwnPropertyDescriptor(
          HTMLTextAreaElement.prototype,
          "value"
        )?.set;
        if (!valueSetter) throw new Error("Textarea value setter is unavailable");
        valueSetter.call(textarea, "Hello @ali #skej");
        textarea.setSelectionRange(10, 10);
        textarea.dispatchEvent(new Event("input", { bubbles: true }));
      });
      await act(async () => new Promise((resolve) => setTimeout(resolve, 200)));

      expect(container.querySelector('[role="listbox"]')?.textContent).toContain(
        "@alice.test"
      );
      await act(async () => {
        textarea.dispatchEvent(
          new KeyboardEvent("keydown", { bubbles: true, key: "Enter" })
        );
      });
      await new Promise((resolve) => setTimeout(resolve, 0));

      expect(textarea.value).toBe("Hello @alice.test #skej");
      const output = container.querySelector('[id="post-1-bluesky-output"]');
      expect(output?.querySelector('[data-facet="mention"]')?.textContent).toBe(
        "@alice.test"
      );
      expect(output?.querySelector('[data-facet="mention"]')?.getAttribute("title")).toBe(
        "did:plc:alice"
      );
      expect(output?.querySelector('[data-facet="tag"]')?.textContent).toBe("#skej");
      expect(output?.textContent).toBe("Hello @alice.test #skej");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
