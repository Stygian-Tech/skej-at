import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias SkejXRPCHeaderProvider = @Sendable (SkejXRPCMethod, String, URL) async throws -> [String: String]

public protocol SkejXRPCTransport: Sendable {
    func send(method: SkejXRPCMethod, parameters: [URLQueryItem], body: Data?) async throws -> Data
}

public enum SkejXRPCTransportError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case http(status: Int, error: String?, message: String?)
}

public struct URLSessionSkejXRPCTransport: SkejXRPCTransport, Sendable {
    public let baseURL: URL
    public let session: URLSession
    public let headerProvider: SkejXRPCHeaderProvider

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        headerProvider: @escaping SkejXRPCHeaderProvider = { _, _, _ in [:] }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.headerProvider = headerProvider
    }

    public func send(
        method: SkejXRPCMethod,
        parameters: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appending(path: "xrpc/\(method.nsid)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = parameters.isEmpty ? nil : parameters
        guard let url = components?.url else {
            throw SkejXRPCTransportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.verb
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in try await headerProvider(method, method.verb, url) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SkejXRPCTransportError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(SkejXRPCErrorBody.self, from: data)
            throw SkejXRPCTransportError.http(
                status: http.statusCode,
                error: body?.error,
                message: body?.message
            )
        }
        return data
    }
}

public struct SkejXRPCClient: Sendable {
    public let transport: any SkejXRPCTransport

    public init(transport: any SkejXRPCTransport) {
        self.transport = transport
    }

    public func getSession() async throws -> Viewer {
        try await query(.getSession, as: Viewer.self)
    }

    public func logout() async throws -> OKResponse {
        try await procedure(.logout, SkejEmptyInput(), as: OKResponse.self)
    }

    public func listAccounts() async throws -> ListAccountsResponse {
        try await query(.listAccounts, as: ListAccountsResponse.self)
    }

    public func searchMentions(_ parameters: SkejSearchMentionsParameters) async throws -> SearchMentionsResponse {
        let query = parameters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 64, (1 ... 8).contains(parameters.limit) else {
            throw SkejXRPCTransportError.invalidURL
        }
        return try await self.query(
            .searchMentions,
            parameters: ["q": query, "limit": String(parameters.limit)],
            as: SearchMentionsResponse.self
        )
    }

    public func listTeams() async throws -> ListTeamsResponse {
        try await query(.listTeams, as: ListTeamsResponse.self)
    }

    public func getTeam(_ parameters: SkejTeamParameters) async throws -> TeamSummary {
        try SkejPayloadValidator.validateRecordKey(parameters.teamRkey)
        return try await query(.getTeam, parameters: ["teamRkey": parameters.teamRkey], as: TeamSummary.self)
    }

    public func createTeam(_ input: CreateTeamRequest) async throws -> TeamSummary {
        try await procedure(.createTeam, input, as: TeamSummary.self)
    }

    public func updateTeam(_ input: SkejUpdateTeamInput) async throws -> TeamSummary {
        try SkejPayloadValidator.validateRecordKey(input.teamRkey)
        return try await procedure(.updateTeam, input, as: TeamSummary.self)
    }

    public func transferTeamOwner(_ input: SkejTransferTeamOwnerInput) async throws -> TeamSummary {
        try SkejPayloadValidator.validateRecordKey(input.teamRkey)
        try SkejPayloadValidator.validateDID(input.ownerAdminDid)
        return try await procedure(.transferTeamOwner, input, as: TeamSummary.self)
    }

    public func listMembers(_ parameters: SkejTeamParameters) async throws -> ListMembersResponse {
        try await teamQuery(.listMembers, parameters, as: ListMembersResponse.self)
    }

    public func putMember(_ input: SkejPutMemberInput) async throws -> TeamMemberSummary {
        try await procedure(.putMember, input, as: TeamMemberSummary.self)
    }

    public func listGroups(_ parameters: SkejTeamParameters) async throws -> ListGroupsResponse {
        try await teamQuery(.listGroups, parameters, as: ListGroupsResponse.self)
    }

    public func putGroup(_ input: SkejPutGroupInput) async throws -> TeamGroupSummary {
        try await procedure(.putGroup, input, as: TeamGroupSummary.self)
    }

    public func listBrandGrants(_ parameters: SkejTeamParameters) async throws -> ListBrandGrantsResponse {
        try await teamQuery(.listBrandGrants, parameters, as: ListBrandGrantsResponse.self)
    }

    public func putBrandGrant(_ input: SkejPutBrandGrantInput) async throws -> BrandGrantSummary {
        try await procedure(.putBrandGrant, input, as: BrandGrantSummary.self)
    }

    public func listBrands(_ parameters: SkejTeamParameters) async throws -> ListBrandsResponse {
        try await teamQuery(.listBrands, parameters, as: ListBrandsResponse.self)
    }

    public func putBrand(_ input: SkejPutBrandInput) async throws -> BrandSummary {
        try await procedure(.putBrand, input, as: BrandSummary.self)
    }

    public func getBrandProfile(_ parameters: SkejBrandParameters) async throws -> BrandProfile {
        try SkejPayloadValidator.validateDID(parameters.did)
        return try await query(.getBrandProfile, parameters: ["did": parameters.did], as: BrandProfile.self)
    }

    public func updateBrandProfile(_ input: SkejUpdateBrandProfileInput) async throws -> BrandProfile {
        try SkejPayloadValidator.validateDID(input.did)
        return try await procedure(.updateBrandProfile, input, as: BrandProfile.self)
    }

    public func listSchedules(_ parameters: SkejAccountParameters = .init()) async throws -> ListSchedulesResponse {
        try validateOptionalDID(parameters.accountDid)
        return try await query(.listSchedules, parameters: optionalAccount(parameters.accountDid), as: ListSchedulesResponse.self)
    }

    public func listCalendar(_ parameters: SkejCalendarParameters) async throws -> ListCalendarEventsResponse {
        guard Timestamp.date(from: parameters.from) != nil,
              Timestamp.date(from: parameters.to) != nil,
              parameters.accountDids.count <= 100,
              parameters.statuses.count <= CalendarEventStatus.allCases.count
        else {
            throw SkejXRPCTransportError.invalidURL
        }
        for did in parameters.accountDids {
            try SkejPayloadValidator.validateDID(did)
        }
        var queryItems = [
            URLQueryItem(name: "from", value: parameters.from),
            URLQueryItem(name: "to", value: parameters.to),
        ]
        queryItems.append(contentsOf: parameters.accountDids.map { URLQueryItem(name: "accountDids", value: $0) })
        queryItems.append(contentsOf: parameters.statuses.map { URLQueryItem(name: "status", value: $0.rawValue) })
        let data = try await transport.send(method: .listCalendar, parameters: queryItems, body: nil)
        return try JSONDecoder().decode(ListCalendarEventsResponse.self, from: data)
    }

    public func createSchedule(_ input: SkejCreateScheduleInput) async throws -> ScheduledPostSummary {
        try validateOptionalDID(input.accountDid)
        return try await procedure(.createSchedule, input, as: ScheduledPostSummary.self)
    }

    public func updateSchedule(_ input: SkejUpdateScheduleInput) async throws -> ScheduledPostSummary {
        try validateOptionalDID(input.accountDid)
        try SkejPayloadValidator.validateRecordKey(input.rkey)
        return try await procedure(.updateSchedule, input, as: ScheduledPostSummary.self)
    }

    public func cancelSchedule(_ parameters: SkejScheduleParameters) async throws -> ScheduledPostSummary {
        try await scheduleProcedure(.cancelSchedule, parameters)
    }

    public func retrySchedule(_ parameters: SkejScheduleParameters) async throws -> ScheduledPostSummary {
        try await scheduleProcedure(.retrySchedule, parameters)
    }

    public func duplicateSchedule(_ parameters: SkejScheduleParameters) async throws -> ScheduledPostSummary {
        try await scheduleProcedure(.duplicateSchedule, parameters)
    }

    public func publishNow(_ parameters: SkejScheduleParameters) async throws -> ScheduledPostSummary {
        try await scheduleProcedure(.publishNow, parameters)
    }

    public func recordView(_ parameters: SkejScheduleParameters) async throws -> OKResponse {
        try validate(parameters)
        return try await procedure(.recordView, parameters, as: OKResponse.self)
    }

    public func createLinkPreview(_ input: SkejCreateLinkPreviewInput) async throws -> ExternalEmbed {
        try validateOptionalDID(input.accountDid)
        try SkejPayloadValidator.validateURL(input.url)
        return try await procedure(.createLinkPreview, input, as: ExternalEmbed.self)
    }

    public func listAuditEvents(_ parameters: SkejAccountParameters) async throws -> ListAuditEventsResponse {
        try validateOptionalDID(parameters.accountDid)
        return try await query(.listAuditEvents, parameters: optionalAccount(parameters.accountDid), as: ListAuditEventsResponse.self)
    }

    /// Seeds non-production demo data when the gateway exposes the development procedure.
    public func seedDevelopment() async throws -> OKResponse {
        try await procedure(.seedDevelopment, SkejEmptyInput(), as: OKResponse.self)
    }

    private func teamQuery<Output: Decodable>(_ method: SkejXRPCMethod, _ parameters: SkejTeamParameters, as: Output.Type) async throws -> Output {
        try SkejPayloadValidator.validateRecordKey(parameters.teamRkey)
        return try await query(method, parameters: ["teamRkey": parameters.teamRkey], as: Output.self)
    }

    private func scheduleProcedure(_ method: SkejXRPCMethod, _ parameters: SkejScheduleParameters) async throws -> ScheduledPostSummary {
        try validate(parameters)
        return try await procedure(method, parameters, as: ScheduledPostSummary.self)
    }

    private func validate(_ parameters: SkejScheduleParameters) throws {
        try validateOptionalDID(parameters.accountDid)
        try SkejPayloadValidator.validateRecordKey(parameters.rkey)
    }

    private func validateOptionalDID(_ did: String?) throws {
        if let did { try SkejPayloadValidator.validateDID(did) }
    }

    private func optionalAccount(_ did: String?) -> [String: String] {
        did.map { ["accountDid": $0] } ?? [:]
    }

    private func query<Output: Decodable>(
        _ method: SkejXRPCMethod,
        parameters: [String: String] = [:],
        as: Output.Type
    ) async throws -> Output {
        let items = parameters.keys.sorted().map { URLQueryItem(name: $0, value: parameters[$0]) }
        return try JSONDecoder().decode(Output.self, from: try await transport.send(method: method, parameters: items, body: nil))
    }

    private func procedure<Input: Encodable & Sendable, Output: Decodable>(
        _ method: SkejXRPCMethod,
        _ input: Input,
        as: Output.Type
    ) async throws -> Output {
        let body = try JSONEncoder().encode(input)
        return try JSONDecoder().decode(Output.self, from: try await transport.send(method: method, parameters: [], body: body))
    }
}
