"use client";

import { useParams } from "next/navigation";
import * as React from "react";

import { SkejLogoMark } from "@/components/SkejLogoMark";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { startOAuth } from "@/lib/api";

export function InviteAcceptPage() {
  const parameters = useParams<{ token: string }>();
  const [handle, setHandle] = React.useState("");

  return (
    <main className="grid min-h-dvh place-items-center px-4 py-10">
      <Card className="w-full max-w-lg">
        <CardHeader>
          <div className="mb-3 flex items-center gap-3"><SkejLogoMark /><span className="text-2xl font-black text-primary">Skej</span></div>
          <CardTitle>Accept your team invitation</CardTitle>
          <CardDescription>
            Sign in with the invited Bluesky identity. Skej verifies the resulting DID or handle before adding membership.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3">
          <Input
            autoComplete="username"
            onChange={(event) => setHandle(event.target.value)}
            placeholder="your.handle"
            value={handle}
          />
          <Button
            disabled={!handle.trim()}
            onClick={() => {
              window.location.href = startOAuth(handle, {
                purpose: "invite_accept",
                inviteToken: parameters.token,
                returnTo: "/app/account",
              });
            }}
          >
            Verify and Join Team
          </Button>
        </CardContent>
      </Card>
    </main>
  );
}
