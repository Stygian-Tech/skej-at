import { InviteAcceptPage } from "@/components/InviteAcceptPage";

export default async function InvitePage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  return <InviteAcceptPage token={token} />;
}
