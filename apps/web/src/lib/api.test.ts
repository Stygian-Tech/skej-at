import { afterEach, describe, expect, it, mock } from "bun:test";

import { createSchedule, hydrateLinkPreview, logout, startOAuth } from "@/lib/api";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("api client", () => {
  it("builds an OAuth start URL", () => {
    expect(startOAuth(" sam.skej.at ")).toBe("/oauth/start?handle=sam.skej.at");
  });

  it("posts a schedule record", async () => {
    const fetchMock = mock(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.method).toBe("POST");
      expect(JSON.parse(String(init?.body)).record.$type).toBe("at.skej.schedule");
      return new Response(
        JSON.stringify({
          rkey: "3l6test",
          did: "did:plc:test",
          scheduledFor: "2099-01-01T11:00:00.000Z",
          status: "scheduled",
          attempts: 0,
          record: JSON.parse(String(init?.body)).record,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const result = await createSchedule({
      mode: "post",
      scheduledFor: "2099-01-01T11:00",
      posts: [{ text: "scheduled" }],
    });

    expect(result.rkey).toBe("3l6test");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("posts logout", async () => {
    const fetchMock = mock(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.method).toBe("POST");
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    await logout();

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("hydrates a link preview for the selected account", async () => {
    const controller = new AbortController();
    const fetchMock = mock(async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(String(input)).toBe(
        "/v1/accounts/did:plc:test/link-preview"
      );
      expect(init?.method).toBe("POST");
      expect(init?.signal).toBe(controller.signal);
      expect(JSON.parse(String(init?.body))).toEqual({
        url: "https://example.com/article",
      });
      return new Response(
        JSON.stringify({
          $type: "app.bsky.embed.external",
          external: {
            uri: "https://example.com/article",
            title: "Example",
            description: "Description",
          },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const embed = await hydrateLinkPreview(
      "did:plc:test",
      "https://example.com/article",
      controller.signal
    );

    expect(embed.$type).toBe("app.bsky.embed.external");
    expect(embed.external.title).toBe("Example");
  });
});
