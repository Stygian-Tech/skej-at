import type { GetEngagementOutput, GetEngagementParameters } from "@/lib/analyticsTypes";
import { SkejApiError } from "@/lib/api";

const GET_ENGAGEMENT = "at.skej.analytics.getEngagement";

export async function getEngagement(
  parameters: GetEngagementParameters,
  signal?: AbortSignal
): Promise<GetEngagementOutput> {
  const query = new URLSearchParams({
    from: parameters.from,
    to: parameters.to,
    bucket: parameters.bucket,
    timezone: parameters.timezone,
  });
  for (const did of parameters.accountDids ?? []) query.append("accountDids", did);
  const response = await fetch(`/xrpc/${GET_ENGAGEMENT}?${query.toString()}`, {
    credentials: "include",
    headers: { Accept: "application/json" },
    signal,
  });
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as
      | { message?: string; error?: string }
      | null;
    throw new SkejApiError(
      body?.message ?? "Skej could not load engagement analytics.",
      body?.error ?? "unknown_error",
      response.status
    );
  }
  return (await response.json()) as GetEngagementOutput;
}
