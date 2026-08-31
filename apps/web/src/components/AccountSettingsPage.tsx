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

import { AuthenticatedNav } from "@/components/AuthenticatedNav";
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
import { cn } from "@/lib/utils";
import {
  addTeamMember,
  createBrandGrant,
  createTeamInvite,
  createTeam,
  createTeamGroup,
  designateBrand,
  disconnectAccount,
  getBrandProfile,
  getViewer,
  listAccounts,
  listAuditEvents,
  listBrandGrants,
  listBrands,
  listTeamGroups,
  listTeamMembers,
  listTeamInvites,
  listTeams,
  logout,
  revokeTeamInvite,
  setDefaultAccount,
  startOAuth,
  updateBrandProfile,
  updateBrandGrantStatus,
  updateBrandStatus,
  updateTeamGroupStatus,
  updateTeamMemberStatus,
  updateTeamStatus,
  transferTeamOwner,
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
  TeamInvite,
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
  const [teamInvites, setTeamInvites] = React.useState<TeamInvite[]>([]);
  const [teamGroups, setTeamGroups] = React.useState<TeamGroupSummary[]>([]);
  const [brandGrants, setBrandGrants] = React.useState<BrandGrantSummary[]>([]);
  const [brands, setBrands] = React.useState<BrandSummary[]>([]);
  const [brandProfile, setBrandProfile] = React.useState<BrandProfile | null>(null);
  const [newTeamTitle, setNewTeamTitle] = React.useState("");
  const [newMemberDid, setNewMemberDid] = React.useState("");
  const [newMemberRole, setNewMemberRole] = React.useState<TeamRole>("user");
  const [newInviteIdentity, setNewInviteIdentity] = React.useState("");
  const [newInviteRole, setNewInviteRole] = React.useState<TeamRole>("user");
  const [newConnectionHandle, setNewConnectionHandle] = React.useState("");
  const [newGroupName, setNewGroupName] = React.useState("");
  const [newOwnerDid, setNewOwnerDid] = React.useState("");
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
  const proEnabled = viewer?.proFeaturesEnabled === true;
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
            (grant.record.status ?? "active") === "active" &&
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
      setTeamInvites([]);
      setTeamGroups([]);
      setBrandGrants([]);
      setBrands([]);
      return;
    }
    const [members, invites, groups, grants, loadedBrands] = await Promise.all([
      listTeamMembers(teamRkey),
      listTeamInvites(teamRkey).catch(() => []),
      listTeamGroups(teamRkey),
      listBrandGrants(teamRkey),
      listBrands(teamRkey),
    ]);
    setTeamMembers(members);
    setTeamInvites(invites);
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
      if (currentViewer.proFeaturesEnabled === true) {
        await refreshTeams();
      }
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
    if (!proEnabled || !selectedAccountDid || !canManageSelectedBrand) return;
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
  }, [canManageSelectedBrand, proEnabled, selectedAccountDid]);

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
        {isAuthenticated ? <AuthenticatedNav /> : null}

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
          <section
            className={cn(
              "grid gap-5",
              proEnabled && "xl:grid-cols-[minmax(0,0.95fr)_minmax(420px,0.65fr)]"
            )}
          >
            {proEnabled ? (
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
                  {selectedTeam ? (
                    <div className="grid gap-3 rounded-2xl border border-border p-3">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div className="text-sm font-black">Lifecycle</div>
                        <div className="flex items-center gap-2">
                          <Badge variant="outline">{selectedTeam.record.status}</Badge>
                          <Button
                            disabled={isMutating}
                            onClick={() => void runMutation(async () => {
                              await updateTeamStatus(selectedTeam, selectedTeam.record.status === "active" ? "archived" : "active");
                              await refreshTeams();
                            }, selectedTeam.record.status === "active" ? "Team archived." : "Team restored.")}
                            size="sm"
                            variant="ghost"
                          >
                            {selectedTeam.record.status === "active" ? "Archive" : "Restore"}
                          </Button>
                        </div>
                      </div>
                      {selectedTeam.record.ownerAdminDid === viewer?.did ? (
                        <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                          <Input onChange={(event) => setNewOwnerDid(event.target.value)} placeholder="New owner admin DID" value={newOwnerDid} />
                          <Button disabled={!newOwnerDid.trim() || isMutating} onClick={() => void runMutation(async () => {
                            await transferTeamOwner(selectedTeam.rkey, newOwnerDid.trim());
                            setNewOwnerDid("");
                            await refreshTeams();
                          }, "Team ownership transferred.")} variant="outline">Transfer Owner</Button>
                        </div>
                      ) : null}
                    </div>
                  ) : null}
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
                              <div className="flex items-center gap-2">
                                <Badge variant="secondary">{member.record.role}</Badge>
                                <Badge variant="outline">{member.record.status}</Badge>
                                <Button
                                  disabled={isMutating}
                                  onClick={() =>
                                    void runMutation(async () => {
                                      await updateTeamMemberStatus(
                                        selectedTeam.rkey,
                                        member,
                                        member.record.status === "active" ? "disabled" : "active"
                                      );
                                      await loadTeamDetails(selectedTeam.rkey);
                                    }, member.record.status === "active" ? "Member disabled." : "Member restored.")
                                  }
                                  size="sm"
                                  variant="ghost"
                                >
                                  {member.record.status === "active" ? "Disable" : "Restore"}
                                </Button>
                              </div>
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
                      <CardTitle>Invitations</CardTitle>
                      <CardDescription>
                        Invite by handle or DID. Membership is created only after the invited identity completes OAuth.
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="grid gap-4">
                      <div className="grid gap-2">
                        {teamInvites.map((invite) => (
                          <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border px-4 py-3" key={invite.id}>
                            <div>
                              <div className="text-sm font-black">{invite.invitedHandle ?? invite.invitedDid}</div>
                              <div className="text-xs text-muted-foreground">Expires {new Date(invite.expiresAt).toLocaleString()}</div>
                            </div>
                            <div className="flex items-center gap-2">
                              <Badge variant="outline">{invite.status}</Badge>
                              {invite.status === "pending" ? (
                                <Link className="text-xs font-black text-primary underline" href={`/invite/${invite.token}`}>
                                  Acceptance link
                                </Link>
                              ) : null}
                              {invite.status === "pending" ? (
                                <Button
                                  disabled={isMutating}
                                  onClick={() => void runMutation(async () => {
                                    await revokeTeamInvite(invite.id);
                                    await loadTeamDetails(selectedTeam.rkey);
                                  }, "Invitation revoked.")}
                                  size="sm"
                                  variant="ghost"
                                >
                                  Revoke
                                </Button>
                              ) : null}
                            </div>
                          </div>
                        ))}
                        {teamInvites.length === 0 ? <div className="rounded-2xl bg-muted px-4 py-3 text-sm text-muted-foreground">No invitations yet.</div> : null}
                      </div>
                      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_9rem_auto]">
                        <Input
                          placeholder="handle.example or did:plc:…"
                          value={newInviteIdentity}
                          onChange={(event) => setNewInviteIdentity(event.target.value)}
                        />
                        <select
                          aria-label="Invitation role"
                          className="h-11 rounded-2xl border border-border bg-card px-3 text-sm font-black"
                          onChange={(event) => setNewInviteRole(event.target.value as TeamRole)}
                          value={newInviteRole}
                        >
                          <option value="user">User</option>
                          <option value="admin">Admin</option>
                        </select>
                        <Button disabled={!newInviteIdentity.trim() || isMutating} onClick={() => void runMutation(async () => {
                          const identity = newInviteIdentity.trim();
                          await createTeamInvite(
                            selectedTeam.rkey,
                            identity.startsWith("did:") ? { invitedDid: identity } : { invitedHandle: identity.replace(/^@/, "") },
                            newInviteRole
                          );
                          setNewInviteIdentity("");
                          await loadTeamDetails(selectedTeam.rkey);
                        }, "Invitation created.")}>Invite</Button>
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
                                <div className="flex items-center gap-2">
                                  <Badge variant="secondary">{memberDids.length} members</Badge>
                                  <Badge variant="outline">{group.record.status ?? "active"}</Badge>
                                  <Button
                                    disabled={isMutating}
                                    onClick={() => void runMutation(async () => {
                                      await updateTeamGroupStatus(
                                        selectedTeam.rkey,
                                        group,
                                        (group.record.status ?? "active") === "active" ? "archived" : "active"
                                      );
                                      await loadTeamDetails(selectedTeam.rkey);
                                    }, (group.record.status ?? "active") === "active" ? "Group archived." : "Group restored.")}
                                    size="sm"
                                    variant="ghost"
                                  >
                                    {(group.record.status ?? "active") === "active" ? "Archive" : "Restore"}
                                  </Button>
                                </div>
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
                      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                        <Input onChange={(event) => setNewGroupName(event.target.value)} placeholder="New group name" value={newGroupName} />
                        <Button disabled={!newGroupName.trim() || isMutating} onClick={() => void runMutation(async () => {
                          await createTeamGroup(selectedTeam.rkey, newGroupName.trim());
                          setNewGroupName("");
                          await loadTeamDetails(selectedTeam.rkey);
                        }, "Group created.")}>
                          <Plus data-icon="inline-start" /> Add Group
                        </Button>
                      </div>
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
                              <div className="flex items-center gap-2">
                                <Badge variant="secondary">{brand.record.status}</Badge>
                                <Button
                                  disabled={isMutating}
                                  onClick={() => void runMutation(async () => {
                                    await updateBrandStatus(
                                      selectedTeam.rkey,
                                      brand.record.brandDid,
                                      brand.record.status === "active" ? "disabled" : "active"
                                    );
                                    await loadTeamDetails(selectedTeam.rkey);
                                  }, brand.record.status === "active" ? "Brand disabled." : "Brand restored.")}
                                  size="sm"
                                  variant="ghost"
                                >
                                  {brand.record.status === "active" ? "Disable" : "Restore"}
                                </Button>
                              </div>
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
            ) : null}

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
                          {account.status === "needs_reauth"
                            ? `⚠ ${account.handle ?? account.did}`
                            : account.handle ?? account.did}
                        </option>
                      ))}
                    </select>
                    <ChevronDown className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                  </div>
                  <div className="rounded-2xl bg-muted px-4 py-3">
                    <div className="flex items-center justify-between gap-2">
                      <div className="text-sm font-black">
                        {selectedAccount?.displayName ?? selectedAccount?.handle ?? "Account"}
                      </div>
                      {selectedAccount ? (
                        <Badge
                          variant={
                            selectedAccount.status === "needs_reauth"
                              ? "warning"
                              : selectedAccount.status === "disabled"
                                ? "failed"
                                : "success"
                          }
                        >
                          {selectedAccount.status === "needs_reauth"
                            ? "Reconnect"
                            : selectedAccount.status === "disabled"
                              ? "Disabled"
                              : "Connected"}
                        </Badge>
                      ) : null}
                    </div>
                    <div className="truncate text-xs font-semibold text-muted-foreground">
                      {selectedAccount?.did}
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {selectedAccount && !selectedAccount.isDefault ? (
                      <Button
                        disabled={isMutating}
                        onClick={() => void runMutation(async () => {
                          await setDefaultAccount(selectedAccount.did);
                          setAccounts(await listAccounts());
                        }, "Default account updated.")}
                        size="sm"
                        variant="outline"
                      >
                        Make Default
                      </Button>
                    ) : null}
                    {selectedAccount && selectedAccount.did !== viewer?.did ? (
                      <Button
                        disabled={isMutating}
                        onClick={() => void runMutation(async () => {
                          await disconnectAccount(selectedAccount.did);
                          const loaded = await listAccounts();
                          setAccounts(loaded);
                          setSelectedAccountDid(viewer?.did ?? loaded[0]?.did ?? null);
                        }, "Connected account removed.")}
                        size="sm"
                        variant="ghost"
                      >
                        Disconnect
                      </Button>
                    ) : null}
                  </div>
                  {proEnabled ? (
                    <div className="grid gap-3 rounded-2xl border border-border p-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                      <div>
                        <Input
                          aria-label="Account handle to connect"
                          onChange={(event) => setNewConnectionHandle(event.target.value)}
                          placeholder="brand.example"
                          value={newConnectionHandle}
                        />
                        <p className="mt-2 text-xs text-muted-foreground">
                          Legacy secondary ownership is never guessed. Reconnect each older account here to establish explicit access.
                        </p>
                      </div>
                      <Button
                        disabled={!newConnectionHandle.trim()}
                        onClick={() => {
                          window.location.href = startOAuth(newConnectionHandle, {
                            purpose: "connect_account",
                            returnTo: "/app/account",
                          });
                        }}
                      >
                        Connect Account
                      </Button>
                    </div>
                  ) : null}
                  {selectedAccount?.status === "needs_reauth" ? (
                    <div className="flex flex-col gap-3 rounded-2xl border border-destructive/30 px-4 py-3">
                      <p className="text-xs font-semibold text-muted-foreground">
                        Bluesky stopped accepting Skej&apos;s access for this account.
                        Queued posts stay put and publish once you reconnect.
                      </p>
                      <Button
                        onClick={() => {
                          window.location.href = selectedAccount.handle
                            ? startOAuth(selectedAccount.handle, {
                                purpose: "brand_connection",
                                returnTo: "/app/account",
                              })
                            : "/app#connect-account";
                        }}
                        size="sm"
                      >
                        <RefreshCw data-icon="inline-start" />
                        Reconnect {selectedAccount.handle ?? "account"}
                      </Button>
                    </div>
                  ) : null}
                </CardContent>
              </Card>

              {proEnabled && selectedTeam && selectedAccountDid && viewer ? (
                <Card>
                  <CardHeader>
                    <CardTitle>Brand Grants</CardTitle>
                    <CardDescription>
                      Grant yourself capabilities for the selected brand.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="grid gap-4">
                    <div className="grid gap-2">
                      {brandGrants.filter((grant) => grant.record.brandDid === selectedAccountDid).map((grant) => (
                        <div className="grid gap-2 rounded-2xl border border-border p-3" key={grant.uri}>
                          <div className="flex items-center justify-between gap-2">
                            <span className="truncate text-xs font-black">{grant.record.grantee}</span>
                            <Badge variant="outline">{grant.record.status ?? "active"}</Badge>
                          </div>
                          <div className="flex flex-wrap items-center gap-2">
                            {grant.record.capabilities.map((capability) => <Badge key={capability} variant="secondary">{capability}</Badge>)}
                            <Button
                              disabled={isMutating}
                              onClick={() => void runMutation(async () => {
                                await updateBrandGrantStatus(
                                  selectedTeam.rkey,
                                  grant,
                                  (grant.record.status ?? "active") === "active" ? "revoked" : "active"
                                );
                                await loadTeamDetails(selectedTeam.rkey);
                              }, (grant.record.status ?? "active") === "active" ? "Grant revoked." : "Grant restored.")}
                              size="sm"
                              variant="ghost"
                            >
                              {(grant.record.status ?? "active") === "active" ? "Revoke" : "Restore"}
                            </Button>
                          </div>
                        </div>
                      ))}
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {(["create", "approve", "manage", "viewAnalytics"] as BrandCapability[]).map(
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

              {proEnabled && canManageSelectedBrand && selectedAccountDid ? (
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
