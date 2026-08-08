"use client";

import {
  AlertCircle,
  CheckCircle2,
  ChevronDown,
  Copy,
  LogOut,
  Plus,
  RefreshCw,
  Save,
  UserPlus,
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
  createBrandGrant,
  createTeamInvite,
  createTeam,
  designateBrand,
  getBrandProfile,
  getViewer,
  listAccounts,
  listAuditEvents,
  listBrandGrants,
  listBrands,
  listTeamInvites,
  listTeamGroups,
  listTeamMembers,
  listTeams,
  logout,
  revokeTeamInvite,
  resolveIdentity,
  startBrandOAuth,
  updateBrandGrant,
  updateTeamMember,
  updateBrandProfile,
} from "@/lib/api";
import { showProtocolDetails } from "@/lib/environment";
import {
  AuditEvent,
  BrandCapability,
  BrandGrantSummary,
  BrandProfile,
  BrandSummary,
  ManagedAccount,
  ResolvedIdentity,
  TeamInvite,
  TeamMemberSummary,
  TeamGroupSummary,
  TeamRole,
  TeamSummary,
  Viewer,
} from "@/lib/skejTypes";

type AuthStatus = "loading" | "anonymous" | "authenticated";
type PermissionSubject =
  | { type: "member"; did: string }
  | { type: "brand"; did: string };

const BRAND_CAPABILITIES: BrandCapability[] = ["create", "approve", "manage"];

function friendlyError(error: unknown, fallback = "Skej could not update account settings.") {
  return error instanceof Error ? error.message : fallback;
}

function firstInitial(viewer: Viewer | null) {
  return (viewer?.displayName ?? viewer?.handle ?? "S").charAt(0).toUpperCase();
}

function accountInitial(account: ManagedAccount | null | undefined, fallback = "A") {
  return (account?.displayName ?? account?.handle ?? fallback).charAt(0).toUpperCase();
}

function AccountIdentityRow({
  account,
  did,
  showProtocolDetails,
  compact = false,
}: {
  account?: ManagedAccount;
  did: string;
  showProtocolDetails: boolean;
  compact?: boolean;
}) {
  const title = account?.displayName ?? account?.handle ?? "Unknown Account";
  const subtitle = account?.handle ? `@${account.handle}` : "Account";
  return (
    <div className="flex min-w-0 items-center gap-3">
      <div className="grid size-10 shrink-0 place-items-center overflow-hidden rounded-full bg-secondary text-sm font-black text-secondary-foreground">
        {account?.avatar ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            alt=""
            className="size-full object-cover"
            src={account.avatar}
          />
        ) : (
          accountInitial(account)
        )}
      </div>
      <div className="min-w-0">
        <div className="truncate text-sm font-black">{title}</div>
        <div className="truncate text-xs font-semibold text-muted-foreground">
          {subtitle}
        </div>
        {showProtocolDetails ? (
          <div
            className={
              compact
                ? "truncate text-[0.68rem] font-semibold text-muted-foreground/80"
                : "truncate text-xs font-semibold text-muted-foreground/80"
            }
          >
            {did}
          </div>
        ) : null}
      </div>
    </div>
  );
}

function managedAccountFromIdentity(identity: ResolvedIdentity): ManagedAccount {
  return {
    did: identity.did,
    handle: identity.handle,
    displayName: identity.displayName,
    avatar: identity.avatar,
    pdsEndpoint: identity.pdsEndpoint,
    status: "active",
    isDefault: false,
  };
}

function toggleCapability(
  capabilities: BrandCapability[],
  capability: BrandCapability
): BrandCapability[] {
  return capabilities.includes(capability)
    ? capabilities.filter((entry) => entry !== capability)
    : [...capabilities, capability];
}

export function AccountSettingsPage() {
  const [authStatus, setAuthStatus] = React.useState<AuthStatus>("loading");
  const [viewer, setViewer] = React.useState<Viewer | null>(null);
  const [accounts, setAccounts] = React.useState<ManagedAccount[]>([]);
  const [selectedAccountDid, setSelectedAccountDid] = React.useState<string | null>(null);
  const [auditEvents, setAuditEvents] = React.useState<AuditEvent[]>([]);
  const [teams, setTeams] = React.useState<TeamSummary[]>([]);
  const [selectedTeamRkey, setSelectedTeamRkey] = React.useState<string | null>(null);
  const [selectedSubject, setSelectedSubject] = React.useState<PermissionSubject | null>(null);
  const [teamMembers, setTeamMembers] = React.useState<TeamMemberSummary[]>([]);
  const [teamInvites, setTeamInvites] = React.useState<TeamInvite[]>([]);
  const [teamGroups, setTeamGroups] = React.useState<TeamGroupSummary[]>([]);
  const [brandGrants, setBrandGrants] = React.useState<BrandGrantSummary[]>([]);
  const [brands, setBrands] = React.useState<BrandSummary[]>([]);
  const [brandProfile, setBrandProfile] = React.useState<BrandProfile | null>(null);
  const [newTeamTitle, setNewTeamTitle] = React.useState("");
  const [newInviteHandle, setNewInviteHandle] = React.useState("");
  const [newInviteRole, setNewInviteRole] = React.useState<TeamRole>("user");
  const [newBrandDid, setNewBrandDid] = React.useState("");
  const [brandOAuthHandle, setBrandOAuthHandle] = React.useState("");
  const [profileDisplayName, setProfileDisplayName] = React.useState("");
  const [profileDescription, setProfileDescription] = React.useState("");
  const [memberRoleDraft, setMemberRoleDraft] = React.useState<TeamRole>("user");
  const [memberGroupUriDraft, setMemberGroupUriDraft] = React.useState<string[]>([]);
  const [memberBrandCapabilityDraft, setMemberBrandCapabilityDraft] = React.useState<Record<string, BrandCapability[]>>({});
  const [brandMemberCapabilityDraft, setBrandMemberCapabilityDraft] = React.useState<Record<string, BrandCapability[]>>({});
  const [brandGroupCapabilityDraft, setBrandGroupCapabilityDraft] = React.useState<Record<string, BrandCapability[]>>({});
  const [isMutating, setIsMutating] = React.useState(false);
  const [message, setMessage] = React.useState<string | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const teamLoadRequestRef = React.useRef(0);
  const selectedTeamRkeyRef = React.useRef<string | null>(null);
  const selectedAccountDidRef = React.useRef<string | null>(null);

  const isAuthenticated = authStatus === "authenticated" && viewer !== null;
  const selectedTeam =
    teams.find((team) => team.rkey === selectedTeamRkey) ?? teams[0] ?? null;
  const selectedMember =
    selectedSubject?.type === "member"
      ? teamMembers.find((member) => member.record.memberDid === selectedSubject.did) ?? null
      : null;
  const selectedBrand =
    selectedSubject?.type === "brand"
      ? brands.find((brand) => brand.record.brandDid === selectedSubject.did) ?? null
      : null;
  const selectedBrandDid = selectedBrand?.record.brandDid ?? null;
  const canShowProtocolDetails = showProtocolDetails();
  const accountByDid = React.useCallback(
    (did: string) => accounts.find((account) => account.did === did),
    [accounts]
  );
  const selectedAccountCapabilities = new Set(
    selectedBrandDid && viewer
      ? brandGrants
          .filter(
            (grant) =>
              grant.record.brandDid === selectedBrandDid &&
              grant.record.granteeType === "member" &&
              grant.record.grantee === viewer.did
          )
          .flatMap((grant) => grant.record.capabilities)
      : []
  );
  const canManageSelectedBrand =
    selectedBrandDid === viewer?.did || selectedAccountCapabilities.has("manage");
  const grantFor = React.useCallback(
    (brandDid: string, granteeType: "member" | "group", grantee: string) =>
      brandGrants.find(
        (grant) =>
          grant.record.brandDid === brandDid &&
          grant.record.granteeType === granteeType &&
          grant.record.grantee === grantee
      ),
    [brandGrants]
  );
  const mergeResolvedAccount = React.useCallback((identity: ResolvedIdentity) => {
    setAccounts((current) => {
      const nextAccount = managedAccountFromIdentity(identity);
      if (!current.some((account) => account.did === identity.did)) {
        return [...current, nextAccount];
      }
      return current.map((account) =>
        account.did === identity.did
          ? {
              ...account,
              handle: identity.handle ?? account.handle,
              displayName: identity.displayName ?? account.displayName,
              avatar: identity.avatar ?? account.avatar,
              pdsEndpoint: identity.pdsEndpoint ?? account.pdsEndpoint,
            }
          : account
      );
    });
  }, []);

  const loadTeamDetails = React.useCallback(async (teamRkey: string | null) => {
    const requestId = (teamLoadRequestRef.current += 1);
    if (!teamRkey) {
      if (requestId !== teamLoadRequestRef.current) return;
      setTeamMembers([]);
      setTeamInvites([]);
      setTeamGroups([]);
      setBrandGrants([]);
      setBrands([]);
      return;
    }
    const [members, invites, groups, grants, loadedBrands] = await Promise.all([
      listTeamMembers(teamRkey),
      listTeamInvites(teamRkey),
      listTeamGroups(teamRkey),
      listBrandGrants(teamRkey),
      listBrands(teamRkey),
    ]);
    if (requestId !== teamLoadRequestRef.current) return;
    setTeamMembers(members);
    setTeamInvites(invites);
    setTeamGroups(groups);
    setBrandGrants(grants);
    setBrands(loadedBrands);
  }, []);

  const refreshTeams = React.useCallback(async () => {
    const loadedTeams = await listTeams();
    setTeams(loadedTeams);
    const currentTeamRkey = selectedTeamRkeyRef.current;
    const nextTeamRkey =
      currentTeamRkey && loadedTeams.some((team) => team.rkey === currentTeamRkey)
        ? currentTeamRkey
        : loadedTeams[0]?.rkey ?? null;
    selectedTeamRkeyRef.current = nextTeamRkey;
    setSelectedTeamRkey(nextTeamRkey);
    await loadTeamDetails(nextTeamRkey);
  }, [loadTeamDetails]);

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
      const currentSelectedDid = selectedAccountDidRef.current;
      const nextSelectedDid =
        currentSelectedDid && loadedAccounts.some((account) => account.did === currentSelectedDid)
          ? currentSelectedDid
          : defaultDid;
      selectedAccountDidRef.current = nextSelectedDid;
      setSelectedAccountDid(nextSelectedDid);
      setAuditEvents(nextSelectedDid ? await listAuditEvents(nextSelectedDid) : []);
      await refreshTeams();
    } catch {
      setViewer(null);
      setAccounts([]);
      selectedAccountDidRef.current = null;
      selectedTeamRkeyRef.current = null;
      setSelectedAccountDid(null);
      setSelectedTeamRkey(null);
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
    if (!selectedBrandDid || !canManageSelectedBrand) return;
    let cancelled = false;
    void getBrandProfile(selectedBrandDid)
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
  }, [canManageSelectedBrand, selectedBrandDid]);

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

  function inviteURL(token: string) {
    if (typeof window === "undefined") return `/invite/${token}`;
    return `${window.location.origin}/invite/${token}`;
  }

  function selectMemberForEditing(member: TeamMemberSummary) {
    setSelectedSubject({ type: "member", did: member.record.memberDid });
    setMemberRoleDraft(member.record.role);
    setMemberGroupUriDraft(member.record.groupUris ?? []);
    setMemberBrandCapabilityDraft(
      Object.fromEntries(
        brands.map((brand) => [
          brand.record.brandDid,
          grantFor(brand.record.brandDid, "member", member.record.memberDid)
            ?.record.capabilities ?? [],
        ])
      )
    );
  }

  function selectBrandForEditing(brand: BrandSummary) {
    selectedAccountDidRef.current = brand.record.brandDid;
    setSelectedAccountDid(brand.record.brandDid);
    setSelectedSubject({ type: "brand", did: brand.record.brandDid });
    setBrandMemberCapabilityDraft(
      Object.fromEntries(
        teamMembers.map((member) => [
          member.record.memberDid,
          grantFor(brand.record.brandDid, "member", member.record.memberDid)
            ?.record.capabilities ?? [],
        ])
      )
    );
    setBrandGroupCapabilityDraft(
      Object.fromEntries(
        teamGroups.map((group) => [
          group.uri,
          grantFor(brand.record.brandDid, "group", group.uri)?.record.capabilities ?? [],
        ])
      )
    );
    void listAuditEvents(brand.record.brandDid).then(setAuditEvents);
  }

  async function upsertBrandGrantForSubject(
    brandDid: string,
    granteeType: "member" | "group",
    grantee: string,
    capabilities: BrandCapability[]
  ) {
    if (!selectedTeam) return;
    const existingGrant = grantFor(brandDid, granteeType, grantee);
    const grant = { brandDid, granteeType, grantee, capabilities };
    if (existingGrant) {
      await updateBrandGrant(selectedTeam.rkey, existingGrant.rkey, grant);
      return;
    }
    if (capabilities.length > 0) {
      await createBrandGrant(selectedTeam.rkey, grant);
    }
  }

  async function saveSelectedMemberPermissions() {
    if (!selectedTeam || !selectedMember) return;
    await updateTeamMember(
      selectedTeam.rkey,
      selectedMember.record.memberDid,
      memberRoleDraft,
      memberGroupUriDraft
    );
    for (const brand of brands) {
      await upsertBrandGrantForSubject(
        brand.record.brandDid,
        "member",
        selectedMember.record.memberDid,
        memberBrandCapabilityDraft[brand.record.brandDid] ?? []
      );
    }
    await refreshTeams();
  }

  async function saveSelectedBrandPermissions() {
    if (!selectedTeam || !selectedBrandDid) return;
    for (const member of teamMembers) {
      await upsertBrandGrantForSubject(
        selectedBrandDid,
        "member",
        member.record.memberDid,
        brandMemberCapabilityDraft[member.record.memberDid] ?? []
      );
    }
    for (const group of teamGroups) {
      await upsertBrandGrantForSubject(
        selectedBrandDid,
        "group",
        group.uri,
        brandGroupCapabilityDraft[group.uri] ?? []
      );
    }
    await refreshTeams();
  }

  return (
    <main className="min-h-dvh px-4 pb-16 pt-4 text-foreground sm:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-5">
        <header className="flex items-center justify-between gap-3 rounded-[2rem] border border-border bg-card/95 px-4 py-3 shadow-[0_14px_38px_rgba(35,31,32,0.08)] backdrop-blur">
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
          <div className="flex items-center gap-3 rounded-[1.5rem] border border-destructive/30 bg-muted px-4 py-3 text-sm font-bold text-destructive">
            <AlertCircle className="shrink-0" />
            {error}
          </div>
        ) : null}
        {message ? (
          <div className="flex items-center gap-3 rounded-[1.5rem] border border-border bg-secondary px-4 py-3 text-sm font-bold text-secondary-foreground">
            <CheckCircle2 className="shrink-0" />
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
                          selectedTeamRkeyRef.current = rkey;
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
                          selectedTeamRkeyRef.current = team.rkey;
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
                        Invite admins and users by handle. They join after signing in.
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
                            <button
                              className={`flex items-center justify-between gap-3 rounded-2xl border px-4 py-3 text-left transition ${
                                selectedSubject?.type === "member" &&
                                selectedSubject.did === member.record.memberDid
                                  ? "border-ring bg-secondary/30"
                                  : "border-border bg-card hover:bg-muted"
                              }`}
                              key={member.uri}
                              type="button"
                              onClick={() => selectMemberForEditing(member)}
                            >
                              <AccountIdentityRow
                                account={accountByDid(member.record.memberDid)}
                                did={member.record.memberDid}
                                showProtocolDetails={canShowProtocolDetails}
                              />
                              <Badge variant="secondary">{member.record.role}</Badge>
                            </button>
                          ))
                        )}
                      </div>
                      <div className="grid gap-2">
                        {teamInvites.filter((invite) => invite.status === "pending").length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            No pending invitations.
                          </div>
                        ) : (
                          teamInvites.map((invite) => (
                            <div
                              className="grid gap-3 rounded-2xl border border-border bg-card px-4 py-3 sm:grid-cols-[minmax(0,1fr)_auto]"
                              key={invite.id}
                            >
                              <div className="min-w-0">
                                <div className="truncate text-sm font-black">
                                  @{invite.invitedHandle}
                                </div>
                                <div className="truncate text-xs font-semibold text-muted-foreground">
                                  {invite.role} invitation · {invite.status}
                                </div>
                                {canShowProtocolDetails ? (
                                  <div className="truncate text-xs font-semibold text-muted-foreground/80">
                                    {invite.invitedDid}
                                  </div>
                                ) : null}
                              </div>
                              <div className="flex flex-wrap items-center gap-2">
                                <Button
                                  variant="outline"
                                  size="sm"
                                  onClick={() =>
                                    void navigator.clipboard?.writeText(inviteURL(invite.token))
                                  }
                                >
                                  <Copy data-icon="inline-start" />
                                  Copy Link
                                </Button>
                                {invite.status === "pending" ? (
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    disabled={isMutating}
                                    onClick={() =>
                                      void runMutation(async () => {
                                        await revokeTeamInvite(selectedTeam.rkey, invite.id);
                                        await refreshTeams();
                                      }, "Invitation revoked.")
                                    }
                                  >
                                    Revoke
                                  </Button>
                                ) : null}
                              </div>
                            </div>
                          ))
                        )}
                      </div>
                      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_10rem_auto]">
                        <Input
                          placeholder="user.bsky.social"
                          value={newInviteHandle}
                          onChange={(event) => setNewInviteHandle(event.target.value)}
                        />
                        <div className="relative">
                          <select
                            aria-label="Invite Role"
                            className="skej-select-control h-11 w-full rounded-2xl border border-border bg-card px-3 pr-10 text-sm font-black outline-none"
                            value={newInviteRole}
                            onChange={(event) => setNewInviteRole(event.target.value as TeamRole)}
                          >
                            <option value="user">User</option>
                            <option value="admin">Admin</option>
                          </select>
                          <ChevronDown className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                        </div>
                        <Button
                          disabled={!newInviteHandle.trim() || isMutating}
                          onClick={() =>
                            void runMutation(async () => {
                              const invite = await createTeamInvite(
                                selectedTeam.rkey,
                                newInviteHandle.trim(),
                                newInviteRole
                              );
                              const identity = {
                                identifier: invite.invitedHandle,
                                did: invite.invitedDid,
                                pdsEndpoint: "local",
                                handle: invite.invitedHandle,
                                displayName: invite.invitedHandle,
                              };
                              mergeResolvedAccount(identity);
                              setNewInviteHandle("");
                              await refreshTeams();
                            }, "Invitation created.")
                          }
                        >
                          <UserPlus data-icon="inline-start" />
                          Invite
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
                              <div className="grid gap-2">
                                {memberDids.slice(0, 4).map((did) => (
                                  <AccountIdentityRow
                                    account={accountByDid(did)}
                                    compact
                                    did={did}
                                    key={did}
                                    showProtocolDetails={canShowProtocolDetails}
                                  />
                                ))}
                                {memberDids.length > 4 ? (
                                  <span className="text-xs font-semibold text-muted-foreground">
                                    {memberDids.length - 4} more members
                                  </span>
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
                        Designate business or app accounts as brands and grant capabilities.
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="grid gap-4">
                      <div className="grid gap-2">
                        {brands.length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            No brand accounts designated.
                          </div>
                        ) : (
                          brands.map((brand) => (
                            <button
                              className={`flex items-center justify-between gap-3 rounded-2xl border px-4 py-3 text-left transition ${
                                selectedSubject?.type === "brand" &&
                                selectedSubject.did === brand.record.brandDid
                                  ? "border-ring bg-secondary/30"
                                  : "border-border bg-card hover:bg-muted"
                              }`}
                              key={brand.uri}
                              type="button"
                              onClick={() => selectBrandForEditing(brand)}
                            >
                              <AccountIdentityRow
                                account={accountByDid(brand.record.brandDid)}
                                did={brand.record.brandDid}
                                showProtocolDetails={canShowProtocolDetails}
                              />
                              <Badge variant="secondary">{brand.record.status}</Badge>
                            </button>
                          ))
                        )}
                      </div>
                      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                        <Input
                          placeholder={
                            canShowProtocolDetails
                              ? selectedAccountDid ?? "handle or did:plc:brand"
                              : "Handle or account ID"
                          }
                          value={newBrandDid}
                          onChange={(event) => setNewBrandDid(event.target.value)}
                        />
                        <Button
                          disabled={!newBrandDid.trim() || isMutating}
                          onClick={() =>
                            void runMutation(async () => {
                              const identity = await resolveIdentity(newBrandDid.trim());
                              mergeResolvedAccount(identity);
                              const brand = await designateBrand(selectedTeam.rkey, identity.did);
                              const ownerGrantCapabilities: BrandCapability[] = [
                                "create",
                                "approve",
                                "manage",
                              ];
                              const hasOwnerGrant = brandGrants.some(
                                (grant) =>
                                  grant.record.brandDid === brand.record.brandDid &&
                                  grant.record.granteeType === "member" &&
                                  grant.record.grantee === viewer?.did &&
                                  ownerGrantCapabilities.every((capability) =>
                                    grant.record.capabilities.includes(capability)
                                  )
                              );
                              if (viewer && !hasOwnerGrant) {
                                await createBrandGrant(selectedTeam.rkey, {
                                  brandDid: brand.record.brandDid,
                                  granteeType: "member",
                                  grantee: viewer.did,
                                  capabilities: ownerGrantCapabilities,
                                });
                              }
                              selectedAccountDidRef.current = brand.record.brandDid;
                              setSelectedAccountDid(brand.record.brandDid);
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
                  <CardTitle>Permission Editor</CardTitle>
                  <CardDescription>
                    Select a member or brand on the left, then adjust access here.
                  </CardDescription>
                </CardHeader>
                <CardContent className="grid gap-4">
                  {!selectedSubject ? (
                    <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                      Select a team member or brand to edit permissions.
                    </div>
                  ) : null}

                  {selectedMember ? (
                    <>
                      <div className="rounded-2xl bg-muted px-4 py-3">
                        <AccountIdentityRow
                          account={accountByDid(selectedMember.record.memberDid)}
                          did={selectedMember.record.memberDid}
                          showProtocolDetails={canShowProtocolDetails}
                        />
                      </div>
                      <div className="grid gap-2">
                        <label className="text-xs font-black">Team Role</label>
                        <div className="relative">
                          <select
                            aria-label="Team Role"
                            className="skej-select-control h-11 w-full rounded-2xl border border-border bg-card px-3 pr-10 text-sm font-black outline-none"
                            value={memberRoleDraft}
                            onChange={(event) => setMemberRoleDraft(event.target.value as TeamRole)}
                          >
                            <option value="user">User</option>
                            <option value="admin">Admin</option>
                          </select>
                          <ChevronDown className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                        </div>
                      </div>
                      <div className="grid gap-2">
                        <div className="text-xs font-black">Permission Groups</div>
                        {teamGroups.length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            No groups available.
                          </div>
                        ) : (
                          teamGroups.map((group) => (
                            <label
                              className="flex items-center justify-between gap-3 rounded-2xl bg-muted px-4 py-3 text-sm font-bold"
                              key={group.uri}
                            >
                              <span className="truncate">{group.record.name}</span>
                              <input
                                checked={memberGroupUriDraft.includes(group.uri)}
                                type="checkbox"
                                onChange={(event) =>
                                  setMemberGroupUriDraft((current) =>
                                    event.target.checked
                                      ? Array.from(new Set([...current, group.uri]))
                                      : current.filter((uri) => uri !== group.uri)
                                  )
                                }
                              />
                            </label>
                          ))
                        )}
                      </div>
                      <div className="grid gap-3">
                        <div>
                          <div className="text-xs font-black">Brand Access</div>
                          <p className="text-xs font-semibold text-muted-foreground">
                            Direct permissions for this user.
                          </p>
                        </div>
                        {brands.length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            Add a brand before assigning access.
                          </div>
                        ) : (
                          brands.map((brand) => (
                            <div className="grid gap-2 rounded-2xl bg-muted px-4 py-3" key={brand.uri}>
                              <div className="text-sm font-black">
                                {accountByDid(brand.record.brandDid)?.displayName ??
                                  accountByDid(brand.record.brandDid)?.handle ??
                                  "Brand Account"}
                              </div>
                              <div className="flex flex-wrap gap-2">
                                {BRAND_CAPABILITIES.map((capability) => (
                                  <label
                                    className="flex items-center gap-2 rounded-full bg-card px-3 py-2 text-xs font-black"
                                    key={capability}
                                  >
                                    <input
                                      checked={
                                        memberBrandCapabilityDraft[
                                          brand.record.brandDid
                                        ]?.includes(capability) ?? false
                                      }
                                      type="checkbox"
                                      onChange={() =>
                                        setMemberBrandCapabilityDraft((current) => ({
                                          ...current,
                                          [brand.record.brandDid]: toggleCapability(
                                            current[brand.record.brandDid] ?? [],
                                            capability
                                          ),
                                        }))
                                      }
                                    />
                                    {capability}
                                  </label>
                                ))}
                              </div>
                            </div>
                          ))
                        )}
                      </div>
                      <Button
                        disabled={isMutating || !selectedTeam}
                        onClick={() =>
                          void runMutation(saveSelectedMemberPermissions, "Member permissions updated.")
                        }
                      >
                        <Save data-icon="inline-start" />
                        Save Member Permissions
                      </Button>
                    </>
                  ) : null}

                  {selectedBrand ? (
                    <>
                      <div className="rounded-2xl bg-muted px-4 py-3">
                        <AccountIdentityRow
                          account={accountByDid(selectedBrand.record.brandDid)}
                          did={selectedBrand.record.brandDid}
                          showProtocolDetails={canShowProtocolDetails}
                        />
                      </div>
                      <div className="grid gap-3">
                        <div>
                          <div className="text-xs font-black">User Permissions</div>
                          <p className="text-xs font-semibold text-muted-foreground">
                            Who can create, approve, or manage this brand.
                          </p>
                        </div>
                        {teamMembers.length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            Invite users before assigning access.
                          </div>
                        ) : (
                          teamMembers.map((member) => (
                            <div className="grid gap-3 rounded-2xl bg-muted px-4 py-3" key={member.uri}>
                              <AccountIdentityRow
                                account={accountByDid(member.record.memberDid)}
                                compact
                                did={member.record.memberDid}
                                showProtocolDetails={canShowProtocolDetails}
                              />
                              <div className="flex flex-wrap gap-2">
                                {BRAND_CAPABILITIES.map((capability) => (
                                  <label
                                    className="flex items-center gap-2 rounded-full bg-card px-3 py-2 text-xs font-black"
                                    key={capability}
                                  >
                                    <input
                                      checked={
                                        brandMemberCapabilityDraft[
                                          member.record.memberDid
                                        ]?.includes(capability) ?? false
                                      }
                                      type="checkbox"
                                      onChange={() =>
                                        setBrandMemberCapabilityDraft((current) => ({
                                          ...current,
                                          [member.record.memberDid]: toggleCapability(
                                            current[member.record.memberDid] ?? [],
                                            capability
                                          ),
                                        }))
                                      }
                                    />
                                    {capability}
                                  </label>
                                ))}
                              </div>
                            </div>
                          ))
                        )}
                      </div>
                      <div className="grid gap-3">
                        <div>
                          <div className="text-xs font-black">Group Permissions</div>
                          <p className="text-xs font-semibold text-muted-foreground">
                            Access granted through permission groups.
                          </p>
                        </div>
                        {teamGroups.length === 0 ? (
                          <div className="rounded-2xl bg-muted px-4 py-3 text-sm font-semibold text-muted-foreground">
                            No groups available.
                          </div>
                        ) : (
                          teamGroups.map((group) => (
                            <div className="grid gap-2 rounded-2xl bg-muted px-4 py-3" key={group.uri}>
                              <div className="text-sm font-black">{group.record.name}</div>
                              <div className="flex flex-wrap gap-2">
                                {BRAND_CAPABILITIES.map((capability) => (
                                  <label
                                    className="flex items-center gap-2 rounded-full bg-card px-3 py-2 text-xs font-black"
                                    key={capability}
                                  >
                                    <input
                                      checked={
                                        brandGroupCapabilityDraft[group.uri]?.includes(
                                          capability
                                        ) ?? false
                                      }
                                      type="checkbox"
                                      onChange={() =>
                                        setBrandGroupCapabilityDraft((current) => ({
                                          ...current,
                                          [group.uri]: toggleCapability(
                                            current[group.uri] ?? [],
                                            capability
                                          ),
                                        }))
                                      }
                                    />
                                    {capability}
                                  </label>
                                ))}
                              </div>
                            </div>
                          ))
                        )}
                      </div>
                      <Button
                        disabled={isMutating || !selectedTeam}
                        onClick={() =>
                          void runMutation(saveSelectedBrandPermissions, "Brand permissions updated.")
                        }
                      >
                        <Save data-icon="inline-start" />
                        Save Brand Permissions
                      </Button>
                    </>
                  ) : null}
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Connect Brand Account</CardTitle>
                  <CardDescription>
                    OAuth a brand so Skej can post on its behalf.
                  </CardDescription>
                </CardHeader>
                <CardContent className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
                  <Input
                    placeholder="brand.bsky.social"
                    value={brandOAuthHandle}
                    onChange={(event) => setBrandOAuthHandle(event.target.value)}
                  />
                  <Button
                    disabled={!brandOAuthHandle.trim() || isMutating}
                    onClick={() => {
                      window.location.href = startBrandOAuth(brandOAuthHandle.trim());
                    }}
                  >
                    <Plus data-icon="inline-start" />
                    Connect Brand
                  </Button>
                </CardContent>
              </Card>

              {canManageSelectedBrand && selectedBrandDid ? (
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
                          const profile = await updateBrandProfile(selectedBrandDid, {
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

      </div>
    </main>
  );
}
