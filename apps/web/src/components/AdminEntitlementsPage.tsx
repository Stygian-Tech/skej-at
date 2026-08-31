"use client";

import { RefreshCw, Save, ShieldCheck } from "lucide-react";
import * as React from "react";

import { AuthenticatedNav } from "@/components/AuthenticatedNav";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { listProEntitlements, putProEntitlement } from "@/lib/api";
import type { ProEntitlement } from "@/lib/skejTypes";

export function AdminEntitlementsPage() {
  const [entitlements, setEntitlements] = React.useState<ProEntitlement[]>([]);
  const [scope, setScope] = React.useState<ProEntitlement["scope"]>("actor");
  const [subject, setSubject] = React.useState("");
  const [expiresAt, setExpiresAt] = React.useState("");
  const [loading, setLoading] = React.useState(true);
  const [saving, setSaving] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const refresh = React.useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setEntitlements(await listProEntitlements());
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Administrator access is required.");
    } finally {
      setLoading(false);
    }
  }, []);

  React.useEffect(() => {
    const timer = window.setTimeout(() => void refresh(), 0);
    return () => window.clearTimeout(timer);
  }, [refresh]);

  async function save(status: ProEntitlement["status"]) {
    if (!subject.trim()) return;
    setSaving(true);
    setError(null);
    try {
      await putProEntitlement({
        scope,
        subject: subject.trim(),
        status,
        expiresAt: expiresAt ? new Date(expiresAt).toISOString() : undefined,
      });
      setSubject("");
      setExpiresAt("");
      await refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Entitlement update failed.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <main className="min-h-dvh px-4 py-6 text-foreground sm:px-6 lg:px-8">
      <div className="mx-auto grid w-full max-w-6xl gap-5">
        <AuthenticatedNav />
        <header>
          <Badge variant="secondary">Restricted</Badge>
          <h1 className="mt-3 flex items-center gap-3 text-4xl font-black tracking-tight">
            <ShieldCheck /> Pro entitlements
          </h1>
          <p className="mt-2 max-w-3xl text-muted-foreground">
            Manually grant or revoke Skej Pro for an actor DID or an entire team URI. The global Pro flag remains the master kill switch.
          </p>
        </header>

        {error ? <div className="rounded-2xl border border-destructive/30 bg-muted p-4 text-sm font-bold text-destructive">{error}</div> : null}

        <Card>
          <CardHeader>
            <CardTitle>Grant or revoke</CardTitle>
            <CardDescription>Team subjects use the full at://…/at.skej.team/… URI.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-3 md:grid-cols-[9rem_minmax(0,1fr)_14rem_auto_auto]">
            <select
              aria-label="Entitlement scope"
              className="h-11 rounded-2xl border border-border bg-card px-3 text-sm font-black"
              onChange={(event) => setScope(event.target.value as ProEntitlement["scope"])}
              value={scope}
            >
              <option value="actor">Actor</option>
              <option value="team">Team</option>
            </select>
            <Input
              aria-label="Entitlement subject"
              onChange={(event) => setSubject(event.target.value)}
              placeholder={scope === "actor" ? "did:plc:…" : "at://…/at.skej.team/…"}
              value={subject}
            />
            <Input
              aria-label="Optional expiry"
              onChange={(event) => setExpiresAt(event.target.value)}
              type="datetime-local"
              value={expiresAt}
            />
            <Button disabled={saving || !subject.trim()} onClick={() => void save("active")}>
              <Save data-icon="inline-start" /> Grant
            </Button>
            <Button disabled={saving || !subject.trim()} onClick={() => void save("revoked")} variant="outline">
              Revoke
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex-row items-start justify-between gap-3">
            <div>
              <CardTitle>Current entries</CardTitle>
              <CardDescription>Expired entries remain visible for auditability.</CardDescription>
            </div>
            <Button disabled={loading} onClick={() => void refresh()} size="sm" variant="outline">
              <RefreshCw className={loading ? "animate-spin" : undefined} data-icon="inline-start" /> Refresh
            </Button>
          </CardHeader>
          <CardContent className="grid gap-2">
            {entitlements.map((entry) => (
              <div className="grid gap-2 rounded-2xl border border-border p-3 sm:grid-cols-[6rem_minmax(0,1fr)_7rem_auto]" key={`${entry.scope}:${entry.subject}`}>
                <Badge variant="outline">{entry.scope}</Badge>
                <span className="break-all text-sm font-bold">{entry.subject}</span>
                <Badge variant={entry.status === "active" ? "secondary" : "outline"}>{entry.status}</Badge>
                <span className="text-xs text-muted-foreground">{entry.expiresAt ? new Date(entry.expiresAt).toLocaleString() : "No expiry"}</span>
              </div>
            ))}
            {!loading && entitlements.length === 0 ? <p className="text-sm text-muted-foreground">No manual entitlements yet.</p> : null}
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
