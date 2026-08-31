import Foundation

public struct SkejXRPCErrorBody: Codable, Equatable, Sendable {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

public struct SkejEmptyInput: Codable, Equatable, Sendable {
    public init() {}
}

public struct SkejAccountParameters: Codable, Equatable, Sendable {
    public let accountDid: String?

    public init(accountDid: String? = nil) {
        self.accountDid = accountDid
    }
}

public struct SkejCalendarParameters: Codable, Equatable, Sendable {
    public let from: String
    public let to: String
    public let accountDids: [String]
    public let statuses: [CalendarEventStatus]

    public init(
        from: String,
        to: String,
        accountDids: [String] = [],
        statuses: [CalendarEventStatus] = []
    ) {
        self.from = from
        self.to = to
        self.accountDids = accountDids
        self.statuses = statuses
    }
}

public struct ListCalendarEventsResponse: Codable, Equatable, Sendable {
    public let events: [CalendarEventSummary]

    public init(events: [CalendarEventSummary]) {
        self.events = events
    }
}

public struct SkejRequiredAccountInput: Codable, Equatable, Sendable {
    public let accountDid: String

    public init(accountDid: String) {
        self.accountDid = accountDid
    }
}

public struct SkejSearchMentionsParameters: Codable, Equatable, Sendable {
    public let query: String
    public let limit: Int

    public init(query: String, limit: Int = 8) {
        self.query = query
        self.limit = limit
    }
}

public struct SkejTeamParameters: Codable, Equatable, Sendable {
    public let teamRkey: String

    public init(teamRkey: String) {
        self.teamRkey = teamRkey
    }
}

public struct SkejUpdateTeamInput: Codable, Sendable {
    public let teamRkey: String
    public let title: String?
    public let status: TeamStatus?

    public init(teamRkey: String, title: String? = nil, status: TeamStatus? = nil) {
        self.teamRkey = teamRkey
        self.title = title
        self.status = status
    }
}

public struct SkejTransferTeamOwnerInput: Codable, Equatable, Sendable {
    public let teamRkey: String
    public let ownerAdminDid: String

    public init(teamRkey: String, ownerAdminDid: String) {
        self.teamRkey = teamRkey
        self.ownerAdminDid = ownerAdminDid
    }
}

public struct SkejPutMemberInput: Codable, Sendable {
    public let teamRkey: String
    public let memberDid: String
    public let role: TeamRole
    public let status: MembershipStatus?
    public let groupUris: [String]?

    public init(teamRkey: String, memberDid: String, role: TeamRole, status: MembershipStatus? = nil, groupUris: [String]? = nil) {
        self.teamRkey = teamRkey
        self.memberDid = memberDid
        self.role = role
        self.status = status
        self.groupUris = groupUris
    }
}

public struct SkejPutGroupInput: Codable, Sendable {
    public let teamRkey: String
    public let groupRkey: String?
    public let name: String
    public let memberDids: [String]?
    public let brandGrantUris: [String]?
    public let status: TeamGroupStatus?

    public init(teamRkey: String, groupRkey: String? = nil, name: String, memberDids: [String]? = nil, brandGrantUris: [String]? = nil, status: TeamGroupStatus? = nil) {
        self.teamRkey = teamRkey
        self.groupRkey = groupRkey
        self.name = name
        self.memberDids = memberDids
        self.brandGrantUris = brandGrantUris
        self.status = status
    }
}

public struct SkejPutBrandGrantInput: Codable, Sendable {
    public let teamRkey: String
    public let grantRkey: String?
    public let brandDid: String
    public let granteeType: GrantGranteeType
    public let grantee: String
    public let capabilities: [BrandCapability]
    public let status: BrandGrantStatus?

    public init(teamRkey: String, grantRkey: String? = nil, brandDid: String, granteeType: GrantGranteeType, grantee: String, capabilities: [BrandCapability], status: BrandGrantStatus? = nil) {
        self.teamRkey = teamRkey
        self.grantRkey = grantRkey
        self.brandDid = brandDid
        self.granteeType = granteeType
        self.grantee = grantee
        self.capabilities = capabilities
        self.status = status
    }
}

public struct SkejPutBrandInput: Codable, Sendable {
    public let teamRkey: String
    public let brandDid: String
    public let status: ManagedAccountStatus?

    public init(teamRkey: String, brandDid: String, status: ManagedAccountStatus? = nil) {
        self.teamRkey = teamRkey
        self.brandDid = brandDid
        self.status = status
    }
}

public struct SkejCreateInviteInput: Codable, Equatable, Sendable {
    public let teamRkey: String
    public let invitedHandle: String?
    public let invitedDid: String?
    public let role: TeamRole
    public let expiresAt: String?

    public init(
        teamRkey: String,
        invitedHandle: String? = nil,
        invitedDid: String? = nil,
        role: TeamRole = .user,
        expiresAt: String? = nil
    ) {
        self.teamRkey = teamRkey
        self.invitedHandle = invitedHandle
        self.invitedDid = invitedDid
        self.role = role
        self.expiresAt = expiresAt
    }
}

public struct SkejRevokeInviteInput: Codable, Equatable, Sendable {
    public let inviteId: String

    public init(inviteId: String) {
        self.inviteId = inviteId
    }
}

public struct SkejPutEntitlementInput: Codable, Equatable, Sendable {
    public let scope: ProEntitlementScope
    public let subject: String
    public let status: ProEntitlementStatus
    public let expiresAt: String?

    public init(scope: ProEntitlementScope, subject: String, status: ProEntitlementStatus, expiresAt: String? = nil) {
        self.scope = scope
        self.subject = subject
        self.status = status
        self.expiresAt = expiresAt
    }
}

public struct ListTeamInvitesResponse: Codable, Equatable, Sendable {
    public let invites: [TeamInvite]

    public init(invites: [TeamInvite]) {
        self.invites = invites
    }
}

public struct ListProEntitlementsResponse: Codable, Equatable, Sendable {
    public let entitlements: [ProEntitlement]

    public init(entitlements: [ProEntitlement]) {
        self.entitlements = entitlements
    }
}

public struct SkejBrandParameters: Codable, Equatable, Sendable {
    public let did: String

    public init(did: String) {
        self.did = did
    }
}

public struct SkejUpdateBrandProfileInput: Codable, Sendable {
    public let did: String
    public let displayName: String?
    public let description: String?
    public let avatar: String?

    public init(did: String, displayName: String? = nil, description: String? = nil, avatar: String? = nil) {
        self.did = did
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
    }
}

public struct SkejScheduleParameters: Codable, Equatable, Sendable {
    public let accountDid: String?
    public let rkey: String

    public init(accountDid: String? = nil, rkey: String) {
        self.accountDid = accountDid
        self.rkey = rkey
    }
}

public struct SkejCreateScheduleInput: Codable, Sendable {
    public let accountDid: String?
    public let record: SkejScheduleRecord

    public init(accountDid: String? = nil, record: SkejScheduleRecord) {
        self.accountDid = accountDid
        self.record = record
    }
}

public struct SkejUpdateScheduleInput: Codable, Sendable {
    public let accountDid: String?
    public let rkey: String
    public let record: SkejScheduleRecord

    public init(accountDid: String? = nil, rkey: String, record: SkejScheduleRecord) {
        self.accountDid = accountDid
        self.rkey = rkey
        self.record = record
    }
}

public struct SkejCreateLinkPreviewInput: Codable, Equatable, Sendable {
    public let accountDid: String?
    public let url: String

    public init(accountDid: String? = nil, url: String) {
        self.accountDid = accountDid
        self.url = url
    }
}

public enum SkejPayloadValidationError: Error, Equatable, Sendable {
    case invalidDID
    case emptyRecordKey
    case invalidURL
}

public enum SkejPayloadValidator {
    public static func validateDID(_ did: String) throws {
        guard did.hasPrefix("did:"), did.utf8.count <= 2_048 else {
            throw SkejPayloadValidationError.invalidDID
        }
    }

    public static func validateRecordKey(_ rkey: String) throws {
        guard !rkey.isEmpty, rkey.utf8.count <= 512 else {
            throw SkejPayloadValidationError.emptyRecordKey
        }
    }

    public static func validateURL(_ value: String) throws {
        guard value.utf8.count <= 8_192,
              let scheme = URLComponents(string: value)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw SkejPayloadValidationError.invalidURL
        }
    }
}
