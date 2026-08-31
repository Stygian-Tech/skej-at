import { afterEach, describe, expect, it, mock } from "bun:test";

import { getEngagement } from "@/lib/analyticsApi";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("analytics API", () => {
  it("encodes repeated authorized account filters", async () => {
    const fetchMock = mock(async (input: RequestInfo | URL) => {
      const url = new URL(String(input), "https://skej.at");
      expect(url.pathname).toBe("/xrpc/at.skej.analytics.getEngagement");
      expect(url.searchParams.get("from")).toBe("2026-08-01T00:00:00.000Z");
      expect(url.searchParams.get("bucket")).toBe("day");
      expect(url.searchParams.getAll("accountDids")).toEqual([
        "did:plc:one",
        "did:plc:two",
      ]);
      return new Response(
        JSON.stringify({
          generatedAt: "2026-08-30T00:00:00Z",
          status: "live",
          accounts: [],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    const output = await getEngagement({
      from: "2026-08-01T00:00:00.000Z",
      to: "2026-08-30T00:00:00.000Z",
      bucket: "day",
      timezone: "America/Chicago",
      accountDids: ["did:plc:one", "did:plc:two"],
    });

    expect(output.status).toBe("live");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
