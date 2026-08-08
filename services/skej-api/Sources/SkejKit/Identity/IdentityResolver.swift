import Foundation

public struct ResolvedATProtoIdentity: Codable, Equatable, Sendable {
    public let identifier: String
    public let did: String
    public let pdsEndpoint: String
    public let handle: String?
    public let displayName: String?
    public let avatar: String?

    public init(
        identifier: String,
        did: String,
        pdsEndpoint: String,
        handle: String? = nil,
        displayName: String? = nil,
        avatar: String? = nil
    ) {
        self.identifier = identifier
        self.did = did
        self.pdsEndpoint = pdsEndpoint
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
    }
}

public struct IdentityResolver: Sendable {
    private let http: HTTPClient
    private let allowsLocalIdentifiers: Bool

    public init(http: HTTPClient = URLSessionHTTPClient(), allowsLocalIdentifiers: Bool = false) {
        self.http = http
        self.allowsLocalIdentifiers = allowsLocalIdentifiers
    }

    public func resolve(_ rawIdentifier: String) async throws -> ResolvedATProtoIdentity {
        let identifier = normalizedIdentifier(rawIdentifier)
        guard !identifier.isEmpty else {
            throw IdentityResolverError.invalidIdentifier
        }

        if allowsLocalIdentifiers {
            let isDID = identifier.starts(with: "did:")
            let localHandle = isDID ? nil : identifier
            return ResolvedATProtoIdentity(
                identifier: rawIdentifier,
                did: isDID ? identifier : localDID(for: identifier),
                pdsEndpoint: "local",
                handle: localHandle,
                displayName: localHandle
            )
        }

        if identifier.starts(with: "did:") {
            let document = try await fetchDIDDocument(did: identifier)
            return ResolvedATProtoIdentity(
                identifier: rawIdentifier,
                did: identifier,
                pdsEndpoint: try document.pdsEndpoint()
            )
        }

        if let did = try? await resolveHandleViaWellKnown(identifier) {
            let document = try await fetchDIDDocument(did: did)
            return ResolvedATProtoIdentity(
                identifier: rawIdentifier,
                did: did,
                pdsEndpoint: try document.pdsEndpoint(),
                handle: identifier
            )
        }

        let response = try await http.data(HTTPRequest(
            url: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=\(urlEncode(identifier))"
        ))
        let resolved = try JSONDecoder().decode(ResolveHandleResponse.self, from: response.body)
        let document = try await fetchDIDDocument(did: resolved.did)
        return ResolvedATProtoIdentity(
            identifier: rawIdentifier,
            did: resolved.did,
            pdsEndpoint: try document.pdsEndpoint(),
            handle: identifier
        )
    }

    private func resolveHandleViaWellKnown(_ handle: String) async throws -> String {
        let response = try await http.data(HTTPRequest(url: "https://\(handle)/.well-known/atproto-did"))
        guard let did = String(data: response.body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              did.starts(with: "did:")
        else {
            throw IdentityResolverError.invalidIdentifier
        }
        return did
    }

    private func fetchDIDDocument(did: String) async throws -> DIDDocument {
        let url: String
        if did.starts(with: "did:plc:") {
            url = "https://plc.directory/\(did)"
        } else if did.starts(with: "did:web:") {
            let host = did.dropFirst("did:web:".count).replacingOccurrences(of: ":", with: "/")
            url = "https://\(host)/.well-known/did.json"
        } else {
            throw IdentityResolverError.unsupportedDID
        }
        let response = try await http.data(HTTPRequest(url: url))
        return try JSONDecoder().decode(DIDDocument.self, from: response.body)
    }

    private func normalizedIdentifier(_ rawIdentifier: String) -> String {
        var identifier = rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()

        if identifier.starts(with: "at://") {
            identifier = String(identifier.dropFirst("at://".count))
            if let slashIndex = identifier.firstIndex(of: "/") {
                identifier = String(identifier[..<slashIndex])
            }
        }

        return identifier
    }
}

public enum IdentityResolverError: Error, Equatable {
    case invalidIdentifier
    case unsupportedDID
}

private struct ResolveHandleResponse: Codable {
    let did: String
}

private struct DIDDocument: Codable {
    let service: [DIDService]

    func pdsEndpoint() throws -> String {
        guard let service = service.first(where: { $0.id == "#atproto_pds" || $0.type == "AtprotoPersonalDataServer" }) else {
            throw IdentityResolverError.invalidIdentifier
        }
        return service.serviceEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct DIDService: Codable {
    let id: String
    let type: String
    let serviceEndpoint: String
}
