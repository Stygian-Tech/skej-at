import Foundation

public enum OAuthMetadata {
    public static func webClientMetadata(publicOrigin: String) -> [String: JSONValue] {
        let origin = publicOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [
            "client_id": .string("\(origin)/oauth/client-metadata.json"),
            "client_name": .string("Skej"),
            "client_uri": .string(origin),
            "application_type": .string("web"),
            "grant_types": .array([.string("authorization_code"), .string("refresh_token")]),
            "response_types": .array([.string("code")]),
            "redirect_uris": .array([.string("\(origin)/oauth/callback")]),
            "scope": .string("atproto transition:generic repo:at.skej.schedule?create,update,delete repo:app.bsky.feed.post?create"),
            "token_endpoint_auth_method": .string("private_key_jwt"),
            "jwks_uri": .string("\(origin)/oauth/jwks.json"),
            "dpop_bound_access_tokens": .bool(true),
        ]
    }

    public static func jwks() -> [String: [JSONValue]] {
        ["keys": []]
    }
}

