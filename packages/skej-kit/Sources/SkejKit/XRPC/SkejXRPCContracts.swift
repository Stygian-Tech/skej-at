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

    public init(teamRkey: String, groupRkey: String? = nil, name: String, memberDids: [String]? = nil, brandGrantUris: [String]? = nil) {
        self.teamRkey = teamRkey
        self.groupRkey = groupRkey
        self.name = name
        self.memberDids = memberDids
        self.brandGrantUris = brandGrantUris
    }
}

public struct SkejPutBrandGrantInput: Codable, Sendable {
    public let teamRkey: String
    public let grantRkey: String?
    public let brandDid: String
    public let granteeType: GrantGranteeType
    public let grantee: String
    public let capabilities: [BrandCapability]

    public init(teamRkey: String, grantRkey: String? = nil, brandDid: String, granteeType: GrantGranteeType, grantee: String, capabilities: [BrandCapability]) {
        self.teamRkey = teamRkey
        self.grantRkey = grantRkey
        self.brandDid = brandDid
        self.granteeType = granteeType
        self.grantee = grantee
        self.capabilities = capabilities
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
