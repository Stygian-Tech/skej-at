import Foundation

public enum OAuthMetadata {
    public static func webClientMetadata(publicOrigin: String, redirectOrigin: String? = nil) -> [String: JSONValue] {
        let origin = publicOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let redirectBase = redirectOrigin?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? origin
        return [
            "client_id": .string("\(origin)/oauth/client-metadata.json"),
            "client_name": .string("Skej"),
            "client_uri": .string(origin),
            "application_type": .string("web"),
            "grant_types": .array([.string("authorization_code"), .string("refresh_token")]),
            "response_types": .array([.string("code")]),
            "redirect_uris": .array([.string("\(redirectBase)/oauth/callback")]),
            "scope": .string("atproto transition:generic"),
            "token_endpoint_auth_method": .string("none"),
            "dpop_bound_access_tokens": .bool(true),
        ]
    }

    public static func jwks() -> [String: [JSONValue]] {
        ["keys": []]
    }
}
