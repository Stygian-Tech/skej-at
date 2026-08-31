import Foundation

/// Canonical Lexicon-defined methods exposed by the Skej gateway.
public struct SkejXRPCMethod: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case query
        case procedure
    }

    public let nsid: String
    public let kind: Kind
    public let requiresAuthentication: Bool
    public let proOnly: Bool

    public var verb: String { kind == .query ? "GET" : "POST" }

    public static let getSession = Self("at.skej.actor.getSession", .query)
    public static let searchMentions = Self("at.skej.actor.searchMentions", .query)
    public static let logout = Self("at.skej.auth.logout", .procedure)
    public static let listAccounts = Self("at.skej.account.list", .query)
    public static let setDefaultAccount = Self("at.skej.account.setDefault", .procedure, proOnly: true)
    public static let disconnectAccount = Self("at.skej.account.disconnect", .procedure, proOnly: true)

    public static let listTeams = Self("at.skej.team.list", .query, proOnly: true)
    public static let getTeam = Self("at.skej.team.get", .query, proOnly: true)
    public static let createTeam = Self("at.skej.team.create", .procedure, proOnly: true)
    public static let updateTeam = Self("at.skej.team.update", .procedure, proOnly: true)
    public static let transferTeamOwner = Self("at.skej.team.transferOwner", .procedure, proOnly: true)
    public static let listMembers = Self("at.skej.team.listMembers", .query, proOnly: true)
    public static let putMember = Self("at.skej.team.putMember", .procedure, proOnly: true)
    public static let listGroups = Self("at.skej.team.listGroups", .query, proOnly: true)
    public static let putGroup = Self("at.skej.team.putGroup", .procedure, proOnly: true)
    public static let listBrandGrants = Self("at.skej.team.listBrandGrants", .query, proOnly: true)
    public static let putBrandGrant = Self("at.skej.team.putBrandGrant", .procedure, proOnly: true)
    public static let listBrands = Self("at.skej.team.listBrands", .query, proOnly: true)
    public static let putBrand = Self("at.skej.team.putBrand", .procedure, proOnly: true)
    public static let listInvites = Self("at.skej.team.listInvites", .query, proOnly: true)
    public static let createInvite = Self("at.skej.team.createInvite", .procedure, proOnly: true)
    public static let revokeInvite = Self("at.skej.team.revokeInvite", .procedure, proOnly: true)

    public static let getBrandProfile = Self("at.skej.brand.getProfile", .query, proOnly: true)
    public static let updateBrandProfile = Self("at.skej.brand.updateProfile", .procedure, proOnly: true)

    public static let listSchedules = Self("at.skej.schedule.list", .query)
    public static let createSchedule = Self("at.skej.schedule.create", .procedure)
    public static let updateSchedule = Self("at.skej.schedule.update", .procedure)
    public static let cancelSchedule = Self("at.skej.schedule.cancel", .procedure)
    public static let retrySchedule = Self("at.skej.schedule.retry", .procedure, proOnly: true)
    public static let duplicateSchedule = Self("at.skej.schedule.duplicate", .procedure, proOnly: true)
    public static let publishNow = Self("at.skej.schedule.publishNow", .procedure)
    public static let recordView = Self("at.skej.schedule.recordView", .procedure, proOnly: true)

    public static let createLinkPreview = Self("at.skej.preview.createLink", .procedure)
    public static let listAuditEvents = Self("at.skej.audit.list", .query, proOnly: true)
    public static let listCalendar = Self("at.skej.calendar.list", .query, proOnly: true)
    public static let getEngagement = Self("at.skej.analytics.getEngagement", .query, proOnly: true)
    public static let listEntitlements = Self("at.skej.admin.entitlement.list", .query, proOnly: true)
    public static let putEntitlement = Self("at.skej.admin.entitlement.put", .procedure, proOnly: true)
    public static let seedDevelopment = Self("at.skej.dev.seed", .procedure, requiresAuthentication: false, proOnly: true)

    public static let all: [Self] = [
        .getSession, .searchMentions, .logout, .listAccounts, .setDefaultAccount, .disconnectAccount,
        .listTeams, .getTeam, .createTeam, .updateTeam, .transferTeamOwner,
        .listMembers, .putMember, .listGroups, .putGroup, .listBrandGrants,
        .putBrandGrant, .listBrands, .putBrand, .listInvites, .createInvite, .revokeInvite,
        .getBrandProfile, .updateBrandProfile,
        .listSchedules, .createSchedule, .updateSchedule, .cancelSchedule,
        .retrySchedule, .duplicateSchedule, .publishNow, .recordView,
        .createLinkPreview, .listAuditEvents, .listCalendar, .getEngagement,
        .listEntitlements, .putEntitlement, .seedDevelopment,
    ]

    private init(
        _ nsid: String,
        _ kind: Kind,
        requiresAuthentication: Bool = true,
        proOnly: Bool = false
    ) {
        self.nsid = nsid
        self.kind = kind
        self.requiresAuthentication = requiresAuthentication
        self.proOnly = proOnly
    }
}
