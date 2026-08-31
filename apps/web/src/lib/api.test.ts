import { afterEach, describe, expect, it, mock } from "bun:test";

import {
  SkejApiError,
  createSchedule,
  hydrateLinkPreview,
  isReauthRequired,
  logout,
  putProEntitlement,
  startOAuth,
} from "@/lib/api";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("api client", () => {
  it("builds an OAuth start URL", () => {
    expect(startOAuth(" sam.skej.at ")).toBe("/oauth/start?handle=sam.skej.at");
  });

  it("builds purpose-scoped OAuth URLs without an open redirect", () => {
    expect(startOAuth("invitee.example", {
      purpose: "invite_accept",
      inviteToken: "invite-token",
      returnTo: "/app/account",
    })).toBe(
      "/oauth/start?handle=invitee.example&purpose=invite_accept&returnTo=%2Fapp%2Faccount&inviteToken=invite-token"
    );
  });

  it("uses the locked entitlement administration NSID", async () => {
    const fetchMock = mock(async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(String(input)).toBe("/xrpc/at.skej.admin.entitlement.put");
      expect(JSON.parse(String(init?.body))).toEqual({
        scope: "team",
        subject: "at://did:plc:owner/at.skej.team/team",
        status: "active",
      });
      return new Response(JSON.stringify({
        scope: "team",
        subject: "at://did:plc:owner/at.skej.team/team",
        status: "active",
        source: "manual",
        createdAt: "2026-08-30T00:00:00Z",
        updatedAt: "2026-08-30T00:00:00Z",
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    await putProEntitlement({
      scope: "team",
      subject: "at://did:plc:owner/at.skej.team/team",
      status: "active",
    });
  });

  it("posts a schedule record", async () => {
    const fetchMock = mock(async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(String(input)).toBe("/xrpc/at.skej.schedule.create");
      expect(init?.method).toBe("POST");
      const record = JSON.parse(String(init?.body)).record;
      expect(record.$type).toBe("at.skej.schedule");
      expect(record.posts[0].source).toEqual({
        format: "markdown",
        text: "Schedule **this** [link](https://example.com)",
      });
      expect(record.posts[0].text).toBe("Schedule this link");
      expect(record.posts[0].facets[0].features[0].uri).toBe("https://example.com");
      expect(record.posts[0].publishRkey).toMatch(/^[234567abcdefghij][234567abcdefghijklmnopqrstuvwxyz]{12}$/);
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
      posts: [
        {
          source: {
            format: "markdown",
            text: "Schedule **this** [link](https://example.com)",
          },
          text: "stale",
        },
      ],
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
        "/xrpc/at.skej.preview.createLink"
      );
      expect(init?.method).toBe("POST");
      expect(init?.signal).toBe(controller.signal);
      expect(JSON.parse(String(init?.body))).toEqual({
        accountDid: "did:plc:test",
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

  it("surfaces the reconnect code so callers can prompt instead of showing a raw error", async () => {
    globalThis.fetch = mock(
      async () =>
        new Response(
          JSON.stringify({
            error: "account_needs_reauth",
            message: "Reconnect this account to keep posting from it.",
          }),
          { status: 409, headers: { "Content-Type": "application/json" } }
        )
    ) as unknown as typeof fetch;

    const error = await logout().catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(SkejApiError);
    expect(isReauthRequired(error)).toBe(true);
    expect((error as SkejApiError).status).toBe(409);
    expect((error as SkejApiError).message).toBe(
      "Reconnect this account to keep posting from it."
    );
  });

  it("does not mistake other failures for a reconnect prompt", async () => {
    globalThis.fetch = mock(
      async () =>
        new Response(JSON.stringify({ error: "not_found", message: "Schedule not found" }), {
          status: 404,
          headers: { "Content-Type": "application/json" },
        })
    ) as unknown as typeof fetch;

    const error = await logout().catch((caught: unknown) => caught);

    expect(isReauthRequired(error)).toBe(false);
    expect(error).toBeInstanceOf(Error);
    expect((error as Error).message).toBe("Schedule not found");
  });

  it("still produces a readable error when the body is not JSON", async () => {
    globalThis.fetch = mock(
      async () => new Response("<html>502</html>", { status: 502 })
    ) as unknown as typeof fetch;

    const error = await logout().catch((caught: unknown) => caught);

    expect(isReauthRequired(error)).toBe(false);
    expect((error as Error).message).toBe(
      "Skej could not load this right now. Try again soon."
    );
  });
});
