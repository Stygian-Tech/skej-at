"use client";

import {
  AlertCircle,
  CheckCircle2,
  ChevronDown,
  LockKeyhole,
  LogOut,
  Plus,
  RefreshCw,
  Save,
  Users,
} from "lucide-react";
import Link from "next/link";
import * as React from "react";

import { OAuthLoginForm } from "@/components/OAuthLoginForm";
import { SkejLogoMark } from "@/components/SkejLogoMark";
import { ThemeToggle } from "@/components/ThemeToggle";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  addTeamMember,
  createBrandGrant,
  createTeam,
  designateBrand,
  getBrandProfile,
  getViewer,
  listAccounts,
  listAuditEvents,
  listBrandGrants,
  listBrands,
  listTeamGroups,
  listTeamMembers,
  listTeams,
  logout,
  updateBrandProfile,
} from "@/lib/api";
import {
  AuditEvent,
  BrandCapability,
  BrandGrantSummary,
  BrandProfile,
  BrandSummary,
  ManagedAccount,
  TeamMemberSummary,
  TeamGroupSummary,
  TeamRole,
  TeamSummary,
  Viewer,
} from "@/lib/skejTypes";

type AuthStatus = "loading" | "anonymous" | "authenticated";

function friendlyError(error: unknown, fallback = "Skej could not update account settings.") {
  return error instanceof Error ? error.message : fallback;
}

function firstInitial(viewer: Viewer | null) {
  return (viewer?.displayName ?? viewer?.handle ?? "S").charAt(0).toUpperCase();
}

export function AccountSettingsPage() {
  const [authStatus, setAuthStatus] = React.useState<AuthStatus>("loading");
  const [viewer, setViewer] = React.useState<Viewer | null>(null);
  const [accounts, setAccounts] = React.useState<ManagedAccount[]>([]);
  const [selectedAccountDid, setSelectedAccountDid] = React.useState<string | null>(null);
  const [auditEvents, setAuditEvents] = React.useState<AuditEvent[]>([]);
  const [teams, setTeams] = React.useState<TeamSummary[]>([]);
  const [selectedTeamRkey, setSelectedTeamRkey] = React.useState<string | null>(null);
  const [teamMembers, setTeamMembers] = React.useState<TeamMemberSummary[]>([]);
  const [teamGroups, setTeamGroups] = React.useState<TeamGroupSummary[]>([]);
  const [brandGrants, setBrandGrants] = React.useState<BrandGrantSummary[]>([]);
  const [brands, setBrands] = React.useState<BrandSummary[]>([]);
  const [brandProfile, setBrandProfile] = React.useState<BrandProfile | null>(null);
  const [newTeamTitle, setNewTeamTitle] = React.useState("");
  const [newMemberDid, setNewMemberDid] = React.useState("");
  const [newMemberRole, setNewMemberRole] = React.useState<TeamRole>("user");
  const [newBrandDid, setNewBrandDid] = React.useState("");
  const [grantCapabilities, setGrantCapabilities] = React.useState<BrandCapability[]>([
    "create",
    "approve",
  ]);
  const [profileDisplayName, setProfileDisplayName] = React.useState("");
  const [profileDescription, setProfileDescription] = React.useState("");
  const [isMutating, setIsMutating] = React.useState(false);
  const [message, setMessage] = React.useState<string | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  const isAuthenticated = authStatus === "authenticated" && viewer !== null;
  const selectedTeam =
    teams.find((team) => team.rkey === selectedTeamRkey) ?? teams[0] ?? null;
  const selectedAccount =
    accounts.find((account) => account.did === selectedAccountDid) ?? accounts[0] ?? null;
  const accountLabel = React.useCallback(
    (did: string) => accounts.find((account) => account.did === did)?.handle ?? did,
    [accounts]
  );
  const selectedAccountCapabilities = React.useMemo(() => {
    if (!selectedAccountDid || !viewer) return new Set<BrandCapability>();
    return new Set(
      brandGrants
        .filter(
          (grant) =>
            grant.record.brandDid === selectedAccountDid &&
            grant.record.granteeType === "member" &&
            grant.record.grantee === viewer.did
        )
        .flatMap((grant) => grant.record.capabilities)
    );
  }, [brandGrants, selectedAccountDid, viewer]);
  const canManageSelectedBrand =
    selectedAccountDid === viewer?.did || selectedAccountCapabilities.has("manage");

  const loadTeamDetails = React.useCallback(async (teamRkey: string | null) => {
    if (!teamRkey) {
      setTeamMembers([]);
      setTeamGroups([]);
      setBrandGrants([]);
      setBrands([]);
      return;
    }
    const [members, groups, grants, loadedBrands] = await Promise.all([
      listTeamMembers(teamRkey),
      listTeamGroups(teamRkey),
      listBrandGrants(teamRkey),
      listBrands(teamRkey),
    ]);
    setTeamMembers(members);
    setTeamGroups(groups);
    setBrandGrants(grants);
    setBrands(loadedBrands);
  }, []);

  const refreshTeams = React.useCallback(async () => {
    const loadedTeams = await listTeams();
    setTeams(loadedTeams);
    const nextTeamRkey =
      selectedTeamRkey && loadedTeams.some((team) => team.rkey === selectedTeamRkey)
        ? selectedTeamRkey
        : loadedTeams[0]?.rkey ?? null;
    setSelectedTeamRkey(nextTeamRkey);
    await loadTeamDetails(nextTeamRkey);
  }, [loadTeamDetails, selectedTeamRkey]);

  const loadSession = React.useCallback(async () => {
    try {
      const currentViewer = await getViewer();
      setViewer(currentViewer);
      setAuthStatus("authenticated");
      const loadedAccounts = await listAccounts();
      setAccounts(loadedAccounts);
      const defaultDid =
        currentViewer.defaultAccountDid ??
        loadedAccounts.find((account) => account.isDefault)?.did ??
        loadedAccounts[0]?.did ??
        currentViewer.did;
      setSelectedAccountDid(defaultDid);
      setAuditEvents(defaultDid ? await listAuditEvents(defaultDid) : []);
      await refreshTeams();
    } catch {
      setViewer(null);
      setAccounts([]);
      setAuthStatus("anonymous");
    }
  }, [refreshTeams]);

  React.useEffect(() => {
    const timer = window.setTimeout(() => {
      void loadSession();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [loadSession]);

  React.useEffect(() => {
    if (!selectedAccountDid || !canManageSelectedBrand) return;
    let cancelled = false;
    void getBrandProfile(selectedAccountDid)
      .then((profile) => {
        if (cancelled) return;
        setBrandProfile(profile);
        setProfileDisplayName(profile.displayName ?? "");
        setProfileDescription(profile.description ?? "");
      })
      .catch(() => {
        if (!cancelled) setBrandProfile(null);
      });
    return () => {
      cancelled = true;
    };
  }, [canManageSelectedBrand, selectedAccountDid]);

  async function signOut() {
    await logout();
    window.location.href = "/";
  }

  async function runMutation(action: () => Promise<void>, success: string) {
    setIsMutating(true);
    setError(null);
    setMessage(null);
    try {
      await action();
      setMessage(success);
    } catch (mutationError) {
      setError(friendlyError(mutationError));
    } finally {
      setIsMutating(false);
    }
  }

  return (
    <main className="min-h-dvh px-4 pb-16 pt-4 text-foreground sm:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-5">
        <header className="sticky top-11 z-40 flex items-center justify-between gap-3 rounded-[2rem] border border-border bg-card/95 px-4 py-3 shadow-[0_14px_38px_rgba(35,31,32,0.08)] backdrop-blur">
          <Link className="flex min-w-0 items-center gap-3" href="/app">
            <SkejLogoMark />
            <div className="flex min-w-0 flex-col">
              <div className="flex items-center gap-2">
                <span className="text-2xl font-black text-primary">Skej</span>
                <Badge variant="sunny">Alpha</Badge>
              </div>
              <span className="truncate text-xs font-bold text-muted-foreground">
                Admin Panel
              </span>
            </div>
          </Link>
          <div className="flex items-center gap-2">
            <ThemeToggle />
            {viewer ? (
              <div className="flex h-12 items-center gap-1 rounded-full border border-border bg-card p-1">
                <div className="grid size-10 place-items-center rounded-full bg-secondary text-base font-black text-secondary-foreground">
                  {firstInitial(viewer)}
                </div>
                <Button
                  aria-label="Log Out"
                  className="size-10 rounded-full border border-border bg-background/80 p-0"
                  disabled={isMutating}
                  onClick={() => void signOut()}
                  size="icon"
                  variant="ghost"
                >
                  <LogOut />
                </Button>
              </div>
            ) : null}
          </div>
        </header>

        {error ? (
          <div className="flex items-start gap-3 rounded-[1.5rem] border border-destructive/30 bg-muted px-4 py-3 text-sm font-bold text-destructive">
            <AlertCircle className="mt-0.5 shrink-0" />
            {error}
          </div>
        ) : null}
        {message ? (
          <div className="flex items-start gap-3 rounded-[1.5rem] border border-border bg-secondary px-4 py-3 text-sm font-bold text-secondary-foreground">
            <CheckCircle2 className="mt-0.5 shrink-0" />
            {message}
          </div>
        ) : null}

        {authStatus === "loading" ? (
          <Card>
            <CardContent className="p-5 text-sm font-bold text-muted-foreground">
              Loading Admin Panel...
            </CardContent>
          </Card>
        ) : null}

        {!isAuthenticated && authStatus !== "loading" ? (
          <Card>
            <CardHeader>
              <CardTitle>Connect Bluesky</CardTitle>
              <CardDescription>
                Sign in to manage Skej teams, brands, and permissions.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <OAuthLoginForm compact />
            </CardContent>
          </Card>
        ) : null}

        {isAuthenticated ? (
          <section className="grid gap-5 xl:grid-cols-[minmax(0,0.95fr)_minmax(420px,0.65fr)]">
            <div className="grid gap-5">
              <Card>
                <CardHeader>
                  <CardTitle>Teams</CardTitle>
                  <CardDescription>
                    Teams define admins, users, groups, and brand permission grants.
                  </CardDescription>
                </CardHeader>
                <CardContent className="grid gap-4">
                  <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                    <div className="relative">
                      <select
                        aria-label="Team"
                        className="skej-select-control h-11 w-full rounded-2xl border border-border bg-card px-3 pr-10 text-sm font-black outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        value={selectedTeam?.rkey ?? ""}
                        onChange={(event) => {
                          const rkey = event.target.value || null;
                          setSelectedTeamRkey(rkey);
                          void loadTeamDetails(rkey);
                        }}
                      >
                        <option value="">No Team Selected</option>
                        {teams.map((team) => (
                          <option key={team.rkey} value={team.rkey}>
                            {team.record.title}
                          </option>
                        ))}
                      </select>
                      <ChevronDown className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                    </div>
                    <Button variant="outline" onClick={() => void refreshTeams()}>
                      <RefreshCw data-icon="inline-start" />
                      Refresh
                    </Button>
                  </div>
                  <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                    <Input
                      placeholder="New team name"
                      value={newTeamTitle}
                      onChange={(event) => setNewTeamTitle(event.target.value)}
                    />
                    <Button
                      disabled={!newTeamTitle.trim() || isMutating}
                      onClick={() =>
                        void runMutation(async () => {
                          const team = await createTeam(newTeamTitle.trim());
                          setNewTeamTitle("");
                          setSelectedTeamRkey(team.rkey);
                          await refreshTeams();
                        }, "Team created.")
                      }
                    >
                      <Plus data-icon="inline-start" />
                      Create Team
                    </Button>
                  </div>
                </CardContent>
              </Card>

              {selectedTeam ? (
                <>
                  <Card>
                    <CardHeader>
                      <CardTitle>Members</CardTitle>
                      <CardDescription>
                        Add admins and users by ATProto DID.
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="grid gap-4">
                      <div className="grid gap-2">
                        {teamMembers.length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            No team members yet.
                          </div>
                        ) : (
                          teamMembers.map((member) => (
                            <div
                              className="flex items-center justify-between gap-3 rounded-2xl border border-border bg-card px-4 py-3"
                              key={member.uri}
                            >
                              <span className="truncate text-sm font-black">
                                {member.record.memberDid}
                              </span>
                              <Badge variant="secondary">{member.record.role}</Badge>
                            </div>
                          ))
                        )}
                      </div>
                      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_10rem_auto]">
                        <Input
                          placeholder="did:plc:..."
                          value={newMemberDid}
                          onChange={(event) => setNewMemberDid(event.target.value)}
                        />
                        <div className="relative">
                          <select
                            aria-label="Member Role"
                            className="skej-select-control h-11 w-full rounded-2xl border border-border bg-card px-3 pr-10 text-sm font-black outline-none"
                            value={newMemberRole}
                            onChange={(event) => setNewMemberRole(event.target.value as TeamRole)}
                          >
                            <option value="user">User</option>
                            <option value="admin">Admin</option>
                          </select>
                          <ChevronDown className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                        </div>
                        <Button
                          disabled={!newMemberDid.trim() || isMutating}
                          onClick={() =>
                            void runMutation(async () => {
                              await addTeamMember(
                                selectedTeam.rkey,
                                newMemberDid.trim(),
                                newMemberRole
                              );
                              setNewMemberDid("");
                              await refreshTeams();
                            }, "Member added.")
                          }
                        >
                          <Users data-icon="inline-start" />
                          Add
                        </Button>
                      </div>
                    </CardContent>
	                  </Card>

                  <Card>
                    <CardHeader>
                      <CardTitle>Groups</CardTitle>
                      <CardDescription>
                        Permission bundles for members and brand grants.
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="grid gap-2">
                      {teamGroups.length === 0 ? (
                        <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                          No groups yet.
                        </div>
                      ) : (
                        teamGroups.map((group) => {
                          const memberDids = group.record.memberDids ?? [];
                          return (
                            <div
                              className="grid gap-3 rounded-2xl border border-border bg-card px-4 py-3"
                              key={group.uri}
                            >
                              <div className="flex items-center justify-between gap-3">
                                <span className="truncate text-sm font-black">
                                  {group.record.name}
                                </span>
                                <Badge variant="secondary">{memberDids.length} members</Badge>
                              </div>
                              <div className="grid gap-1 text-xs font-semibold text-muted-foreground">
                                {memberDids.slice(0, 4).map((did) => (
                                  <span className="truncate" key={did}>
                                    {did}
                                  </span>
                                ))}
                                {memberDids.length > 4 ? (
                                  <span>{memberDids.length - 4} more members</span>
                                ) : null}
                              </div>
                              <div className="text-xs font-black text-muted-foreground">
                                {group.record.brandGrantUris?.length ?? 0} Brand Grants
                              </div>
                            </div>
                          );
                        })
                      )}
                    </CardContent>
                  </Card>

                  <Card>
                    <CardHeader>
                      <CardTitle>Brands</CardTitle>
                      <CardDescription>
                        Designate business or app DIDs as brands and grant capabilities.
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="grid gap-4">
                      <div className="grid gap-2">
                        {brands.length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            No brand DIDs designated.
                          </div>
                        ) : (
                          brands.map((brand) => (
                            <div
                              className="flex items-center justify-between gap-3 rounded-2xl border border-border bg-card px-4 py-3"
                              key={brand.uri}
                            >
	                              <span className="truncate text-sm font-black">
	                                {accountLabel(brand.record.brandDid)}
	                              </span>
                              <Badge variant="secondary">{brand.record.status}</Badge>
                            </div>
                          ))
                        )}
                      </div>
                      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                        <Input
                          placeholder={selectedAccountDid ?? "did:plc:brand"}
                          value={newBrandDid}
                          onChange={(event) => setNewBrandDid(event.target.value)}
                        />
                        <Button
                          disabled={!newBrandDid.trim() || isMutating}
                          onClick={() =>
                            void runMutation(async () => {
                              await designateBrand(selectedTeam.rkey, newBrandDid.trim());
                              setNewBrandDid("");
                              await refreshTeams();
                            }, "Brand designated.")
                          }
                        >
                          <Plus data-icon="inline-start" />
                          Add Brand
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                </>
              ) : null}
            </div>

            <aside className="grid content-start gap-5">
              <Card>
                <CardHeader>
                  <CardTitle>Connected Account</CardTitle>
                  <CardDescription>
                    Pick the brand/account to inspect and manage.
                  </CardDescription>
                </CardHeader>
                <CardContent className="grid gap-4">
                  <div className="relative">
                    <select
                      aria-label="Connected Account"
                      className="skej-select-control h-11 w-full rounded-2xl border border-border bg-card px-3 pr-10 text-sm font-black outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      value={selectedAccountDid ?? ""}
                      onChange={(event) => {
                        setSelectedAccountDid(event.target.value);
                        void listAuditEvents(event.target.value).then(setAuditEvents);
                      }}
                    >
                      {accounts.map((account) => (
                        <option key={account.did} value={account.did}>
                          {account.handle ?? account.did}
                        </option>
                      ))}
                    </select>
                    <ChevronDown className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                  </div>
                  <div className="rounded-2xl bg-muted px-4 py-3">
                    <div className="text-sm font-black">
                      {selectedAccount?.displayName ?? selectedAccount?.handle ?? "Account"}
                    </div>
                    <div className="truncate text-xs font-semibold text-muted-foreground">
                      {selectedAccount?.did}
                    </div>
                  </div>
                </CardContent>
              </Card>

              {selectedTeam && selectedAccountDid && viewer ? (
                <Card>
                  <CardHeader>
                    <CardTitle>Brand Grants</CardTitle>
                    <CardDescription>
                      Grant yourself capabilities for the selected brand.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="grid gap-4">
                    <div className="flex flex-wrap gap-2">
                      {(["create", "approve", "manage"] as BrandCapability[]).map(
                        (capability) => (
                          <label
                            className="flex items-center gap-2 rounded-full bg-muted px-3 py-2 text-xs font-black"
                            key={capability}
                          >
                            <input
                              checked={grantCapabilities.includes(capability)}
                              type="checkbox"
                              onChange={(event) =>
                                setGrantCapabilities((current) =>
                                  event.target.checked
                                    ? Array.from(new Set([...current, capability]))
                                    : current.filter((entry) => entry !== capability)
                                )
                              }
                            />
                            {capability}
                          </label>
                        )
                      )}
                    </div>
                    <Button
                      disabled={grantCapabilities.length === 0 || isMutating}
                      onClick={() =>
                        void runMutation(async () => {
                          await createBrandGrant(selectedTeam.rkey, {
                            brandDid: selectedAccountDid,
                            granteeType: "member",
                            grantee: viewer.did,
                            capabilities: grantCapabilities,
                          });
                          await refreshTeams();
                        }, "Brand permissions granted.")
                      }
                    >
                      <Plus data-icon="inline-start" />
                      Grant Me Selected Brand
                    </Button>
                  </CardContent>
                </Card>
              ) : null}

              {canManageSelectedBrand && selectedAccountDid ? (
                <Card>
                  <CardHeader>
                    <CardTitle>Brand Profile</CardTitle>
                    <CardDescription>
                      Public account details for the selected brand.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="grid gap-3">
                    <Input
                      placeholder="Display name"
                      value={profileDisplayName}
                      onChange={(event) => setProfileDisplayName(event.target.value)}
                    />
                    <Input
                      placeholder="Description"
                      value={profileDescription}
                      onChange={(event) => setProfileDescription(event.target.value)}
                    />
                    <Button
                      disabled={isMutating}
                      onClick={() =>
                        void runMutation(async () => {
                          const profile = await updateBrandProfile(selectedAccountDid, {
                            displayName: profileDisplayName,
                            description: profileDescription,
                            avatar: brandProfile?.avatar,
                          });
                          setBrandProfile(profile);
                        }, "Brand profile updated.")
                      }
                    >
                      <Save data-icon="inline-start" />
                      Save Profile
                    </Button>
                  </CardContent>
                </Card>
              ) : null}

              <Card>
                <CardHeader>
                  <CardTitle>Audit Trail</CardTitle>
                  <CardDescription>
                    Recent scheduler, team, brand, and permission events.
                  </CardDescription>
                </CardHeader>
                <CardContent className="grid gap-2">
                  {auditEvents.length === 0 ? (
                    <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                      No recent events.
                    </div>
                  ) : (
                    auditEvents.slice(0, 12).map((event) => (
                      <div className="rounded-2xl bg-muted px-4 py-3" key={event.id}>
                        <div className="text-xs font-black">{event.action}</div>
                        <div className="text-xs font-semibold text-muted-foreground">
                          {event.message}
                        </div>
                      </div>
                    ))
                  )}
                </CardContent>
              </Card>
            </aside>
          </section>
        ) : null}

        <Link
          className="inline-flex items-center gap-2 text-sm font-black text-muted-foreground hover:text-foreground"
          href="/app"
        >
          <LockKeyhole className="size-4" />
          Back to Scheduler
        </Link>
      </div>
    </main>
  );
}
