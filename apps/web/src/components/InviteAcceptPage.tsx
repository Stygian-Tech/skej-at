"use client";

import { CheckCircle2, LockKeyhole } from "lucide-react";
import Link from "next/link";
import * as React from "react";

import { SkejLogoMark } from "@/components/SkejLogoMark";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getInvite, startInviteOAuth } from "@/lib/api";
import { TeamInvite } from "@/lib/skejTypes";

export function InviteAcceptPage({ token }: { token: string }) {
  const [invite, setInvite] = React.useState<TeamInvite | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [isLoading, setIsLoading] = React.useState(true);
  const [isStarting, setIsStarting] = React.useState(false);

  React.useEffect(() => {
    let cancelled = false;
    void getInvite(token)
      .then((loadedInvite) => {
        if (cancelled) return;
        setInvite(loadedInvite);
        setError(null);
      })
      .catch((loadError) => {
        if (cancelled) return;
        setError(loadError instanceof Error ? loadError.message : "Invitation could not be loaded.");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

  async function acceptInvite() {
    setIsStarting(true);
    setError(null);
    try {
      window.location.href = await startInviteOAuth(token);
    } catch (startError) {
      setError(startError instanceof Error ? startError.message : "Invitation could not be accepted.");
      setIsStarting(false);
    }
  }

  const canAccept = invite?.status === "pending";

  return (
    <main className="min-h-dvh px-4 py-6 text-foreground sm:px-6 lg:px-8">
      <div className="mx-auto grid w-full max-w-2xl gap-5">
        <header className="flex items-center gap-3 rounded-[2rem] border border-border bg-card/95 px-4 py-3 shadow-[0_14px_38px_rgba(35,31,32,0.08)]">
          <SkejLogoMark />
          <div>
            <div className="flex items-center gap-2">
              <span className="text-2xl font-black text-primary">Skej</span>
              <Badge variant="sunny">Invite</Badge>
            </div>
            <span className="text-xs font-bold text-muted-foreground">Join A Team</span>
          </div>
        </header>

        <Card>
          <CardHeader>
            <CardTitle>Team Invitation</CardTitle>
            <CardDescription>
              Sign in with the invited account to join this Skej team.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4">
            {isLoading ? (
              <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                Loading invitation...
              </div>
            ) : null}
            {error ? (
              <div className="rounded-2xl border border-destructive/30 bg-muted px-4 py-3 text-sm font-bold text-destructive">
                {error}
              </div>
            ) : null}
            {invite ? (
              <div className="grid gap-3 rounded-2xl bg-muted px-4 py-4">
                <div>
                  <div className="text-sm font-black">{invite.teamTitle}</div>
                  <div className="text-xs font-semibold text-muted-foreground">
                    Invited account: @{invite.invitedHandle}
                  </div>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Badge variant="secondary">{invite.role}</Badge>
                  <Badge variant={canAccept ? "sunny" : "secondary"}>{invite.status}</Badge>
                </div>
              </div>
            ) : null}
            <Button disabled={!canAccept || isStarting} onClick={() => void acceptInvite()}>
              <LockKeyhole data-icon="inline-start" />
              Accept With Bluesky
            </Button>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}

export function InviteSuccessPage() {
  return (
    <main className="min-h-dvh px-4 py-6 text-foreground sm:px-6 lg:px-8">
      <div className="mx-auto grid w-full max-w-2xl gap-5">
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <CheckCircle2 className="shrink-0 text-secondary" />
            <div>
              <div className="text-lg font-black">Invitation Accepted</div>
              <div className="text-sm font-semibold text-muted-foreground">
                You can now view the team and any brands shared with you.
              </div>
            </div>
          </CardContent>
        </Card>
        <Link
          className="inline-flex h-11 items-center justify-center rounded-full bg-primary px-4 py-2 text-sm font-bold text-primary-foreground shadow-[0_8px_18px_rgba(255,79,109,0.14)] transition hover:bg-primary/90"
          href="/app/account"
        >
          Open Admin Panel
        </Link>
      </div>
    </main>
  );
}
