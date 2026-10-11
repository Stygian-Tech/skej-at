import Crypto
import Foundation
import libsecp256k1
import SkejKit

/// User credentials remain in their PDS; this verifies only short-lived, method-bound delegation.
public struct SkejServiceAuthVerifier: Sendable {
    private let network: SkejATProtoNetwork
    private let http: any HTTPClient
    private let now: @Sendable () -> Date

    public init(network: SkejATProtoNetwork, http: any HTTPClient = ServiceAuthHTTPClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.network = network
        self.http = http
        self.now = now
    }

    public func verify(_ token: String, method: String, store: SQLiteStore) async throws -> String {
        do {
            guard token.utf8.count <= 8192, !network.serviceDID.isEmpty else { throw invalid() }
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3 else { throw invalid() }
            let header = try JSONDecoder().decode(Header.self, from: Self.decode(parts[0]))
            let claims = try JSONDecoder().decode(Claims.self, from: Self.decode(parts[1]))
            let instant = Int(now().timeIntervalSince1970)
            guard header.typ == "JWT", header.kid == nil || header.kid == "#atproto",
                  header.alg == "ES256" || header.alg == "ES256K",
                  claims.aud == network.serviceAudience, claims.lxm == method,
                  claims.iat <= instant + 5, claims.iat >= instant - 65,
                  claims.exp > instant, claims.exp > claims.iat, claims.exp - claims.iat <= 60,
                  !claims.jti.isEmpty, claims.jti.utf8.count <= 128
            else { throw invalid() }
            let key = try await signingKey(issuer: claims.iss)
            let signature = try Self.decode(parts[2])
            let input = Data("\(parts[0]).\(parts[1])".utf8)
            let valid: Bool
            switch header.alg {
            case "ES256K":
                guard key.prefix(2) == Data([0xe7, 0x01]), key.count == 35 else { throw invalid() }
                valid = Self.verifyK256(key: Data(key.dropFirst(2)), signature: signature, input: input)
            default:
                guard key.prefix(2) == Data([0x80, 0x24]), key.count == 35 else { throw invalid() }
                let publicKey = try P256.Signing.PublicKey(compressedRepresentation: key.dropFirst(2))
                let sig = try P256.Signing.ECDSASignature(rawRepresentation: signature)
                valid = publicKey.isValidSignature(sig, for: input)
            }
            guard valid, try await store.claimServiceAuth(issuer: claims.iss, jti: claims.jti, expiresAt: claims.exp, now: instant) else { throw invalid() }
            return claims.iss
        } catch {
            // Do not log bearer material, issuer URLs, or failed responses.
            throw invalid()
        }
    }

    private func signingKey(issuer: String) async throws -> Data {
        let url: String
        if issuer.hasPrefix("did:plc:") {
            let suffix = issuer.dropFirst(8)
            guard suffix.count == 24, suffix.allSatisfy({ "abcdefghijklmnopqrstuvwxyz234567".contains($0) }), !network.plcOrigin.isEmpty else { throw invalid() }
            url = "\(network.plcOrigin)/\(issuer)"
        } else if issuer.hasPrefix("did:web:") {
            let parts = issuer.dropFirst(8).split(separator: ":", omittingEmptySubsequences: false)
            guard let authority = parts.first?.removingPercentEncoding,
                  !authority.contains("/"), !authority.contains("@"), !authority.contains("?"), !authority.contains("#"),
                  let origin = SkejATProtoNetwork.origin("https://" + authority), network.didWebOrigins.contains(origin),
                  parts.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }) && $0 != "." && $0 != ".." })
            else { throw invalid() }
            let path = parts.count == 1 ? "/.well-known/did.json" : "/" + parts.dropFirst().joined(separator: "/") + "/did.json"
            url = origin + path
        } else { throw invalid() }
        let response = try await http.data(HTTPRequest(url: url))
        guard (200..<300).contains(response.statusCode), response.body.count <= 128 * 1024 else { throw invalid() }
        let document = try JSONDecoder().decode(Document.self, from: response.body)
        let keys = document.verificationMethod.filter { $0.id == issuer + "#atproto" }
        guard document.id == issuer, keys.count == 1, let key = keys.first,
              key.controller == issuer, key.type == "Multikey", let multibase = key.publicKeyMultibase,
              multibase.hasPrefix("z") else { throw invalid() }
        return try Self.base58(String(multibase.dropFirst()))
    }

    private static func verifyK256(key: Data, signature: Data, input: Data) -> Bool {
        guard signature.count == 64, let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_VERIFY)) else { return false }
        defer { secp256k1_context_destroy(context) }
        var publicKey = secp256k1_pubkey()
        var parsed = secp256k1_ecdsa_signature()
        guard secp256k1_ec_pubkey_parse(context, &publicKey, Array(key), key.count) == 1,
              secp256k1_ecdsa_signature_parse_compact(context, &parsed, Array(signature)) == 1 else { return false }
        // JWT ECDSA permits either S representation; libsecp verifies normalized S.
        var normalized = secp256k1_ecdsa_signature()
        _ = secp256k1_ecdsa_signature_normalize(context, &normalized, &parsed)
        return secp256k1_ecdsa_verify(context, &normalized, Array(SHA256.hash(data: input)), &publicKey) == 1
    }

    private func invalid() -> APIError { APIError(status: .unauthorized, code: "InvalidServiceAuth", message: "A valid account-bound Skej service token is required") }

    private static func decode(_ value: Substring) throws -> Data {
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw SkejCryptoError.encodingFailed }
        let text = String(value).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: text + String(repeating: "=", count: (4 - text.count % 4) % 4)) else { throw SkejCryptoError.encodingFailed }
        return data
    }

    private static func base58(_ value: String) throws -> Data {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        guard !value.isEmpty, value.count <= 100 else { throw SkejCryptoError.encodingFailed }
        var bytes = [UInt8]()
        for character in value {
            guard let digit = alphabet.firstIndex(of: character) else { throw SkejCryptoError.encodingFailed }
            var carry = digit
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 255)
                carry >>= 8
            }
            while carry > 0 { bytes.append(UInt8(carry & 255)); carry >>= 8 }
        }
        return Data(Array(repeating: 0, count: value.prefix(while: { $0 == "1" }).count) + bytes.reversed())
    }

    private struct Header: Decodable { let typ: String; let alg: String; let kid: String? }
    private struct Claims: Decodable { let iss: String; let aud: String; let iat: Int; let exp: Int; let lxm: String; let jti: String }
    private struct Document: Decodable { let id: String; let verificationMethod: [Key] }
    private struct Key: Decodable { let id: String; let controller: String; let type: String; let publicKeyMultibase: String? }
}
