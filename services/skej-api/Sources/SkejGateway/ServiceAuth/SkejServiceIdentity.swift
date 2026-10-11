import SkejKit

public enum SkejServiceIdentity {
    public static func document(network: SkejATProtoNetwork) -> [String: JSONValue] {
        [
            "@context": .array([.string("https://www.w3.org/ns/did/v1")]),
            "id": .string(network.serviceDID),
            "service": .array([.object([
                "id": .string(network.serviceAudience),
                "type": .string("SkejScheduler"),
                "serviceEndpoint": .string(network.apiOrigin),
            ])]),
        ]
    }
}
