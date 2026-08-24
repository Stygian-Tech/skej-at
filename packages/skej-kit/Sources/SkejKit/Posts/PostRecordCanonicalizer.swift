import Foundation

public enum PostRecordCanonicalizer {
    private static let urlExpression = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"']+"#,
        options: [.caseInsensitive]
    )
    // Mirrors the tag detection in @atproto/api: a hashtag starts the text or follows
    // whitespace, must hold at least one character that is not a digit, punctuation, or
    // an invisible separator, and its facet range covers the leading "#".
    private static let tagExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)([#\uFF03](?!\uFE0F)[^\s\u00AD\u2060\u200A\u200B\u200C\u200D\u20E2]*[^\d\s\p{P}\u00AD\u2060\u200A\u200B\u200C\u200D\u20E2]+[^\s\u00AD\u2060\u200A\u200B\u200C\u200D\u20E2]*)"#
    )
    private static let maxTagLength = 64
    private static let simpleTrailingPunctuation = CharacterSet(charactersIn: ".,!?;:")
    private static let closingPairs: [(Character, Character)] = [
        ("(", ")"),
        ("[", "]"),
        ("{", "}"),
    ]

    public static func canonicalize(_ plan: PostPlan) -> PostPlan {
        PostPlan(
            text: plan.text,
            facets: facets(in: plan.text, preserving: plan.facets),
            reply: plan.reply,
            embed: normalizeEmbed(plan.embed),
            langs: plan.langs,
            labels: plan.labels,
            tags: plan.tags
        )
    }

    public static func canonicalizeFeedPost(_ value: JSONValue) -> JSONValue {
        guard case var .object(post) = value,
              case let .string(text)? = post["text"]
        else {
            return value
        }

        let existingFacets: [JSONValue]?
        if case let .array(facets)? = post["facets"] {
            existingFacets = facets
        } else {
            existingFacets = nil
        }
        if let facets = facets(in: text, preserving: existingFacets) {
            post["facets"] = .array(facets)
        } else {
            post.removeValue(forKey: "facets")
        }
        if let embed = normalizeEmbed(post["embed"]) {
            post["embed"] = embed
        }
        return .object(post)
    }

    public static func feedPostValue(
        _ plan: PostPlan,
        createdAt: String
    ) throws -> [String: JSONValue] {
        let canonical = canonicalize(plan)
        var post: [String: JSONValue] = [
            "$type": .string("app.bsky.feed.post"),
            "text": .string(canonical.text),
            "createdAt": .string(createdAt),
        ]
        if let facets = canonical.facets {
            post["facets"] = try facets.skejJSONValue()
        }
        if let reply = canonical.reply {
            post["reply"] = try reply.skejJSONValue()
        }
        if let embed = canonical.embed {
            post["embed"] = try embed.skejJSONValue()
        }
        if let langs = canonical.langs, !langs.isEmpty {
            post["langs"] = .array(langs.map { .string($0) })
        }
        if let labels = canonical.labels, !labels.isEmpty {
            post["labels"] = .object([
                "$type": .string("com.atproto.label.defs#selfLabels"),
                "values": .array(labels.map { .object(["val": .string($0)]) }),
            ])
        }
        if let tags = canonical.tags, !tags.isEmpty {
            post["tags"] = .array(tags.map { .string($0) })
        }
        return post
    }

    public static func facets(
        in text: String,
        preserving existingFacets: [JSONValue]? = nil
    ) -> [JSONValue]? {
        let links = detectedLinks(in: text)
        let linkRanges = links.map(\.range)
        let tags = detectedTags(in: text).filter { tag in
            !linkRanges.contains { $0.overlaps(tag.range) }
        }
        let detectedRanges = linkRanges + tags.map(\.range)
        var preservedRanges: [Range<Int>] = []
        var facets: [JSONValue] = []
        for facet in (existingFacets ?? []).sorted(by: {
            (facetByteRange($0)?.lowerBound ?? Int.max) <
                (facetByteRange($1)?.lowerBound ?? Int.max)
        }) {
            guard let range = facetByteRange(facet),
                  range.lowerBound >= 0,
                  range.upperBound <= text.utf8.count,
                  range.lowerBound < range.upperBound,
                  !facetContainsGeneratedFeature(facet),
                  !detectedRanges.contains(where: { $0.overlaps(range) }),
                  !preservedRanges.contains(where: { $0.overlaps(range) })
            else {
                continue
            }
            facets.append(facet)
            preservedRanges.append(range)
        }

        facets.append(contentsOf: links.map { link in
            facet(
                range: link.range,
                feature: [
                    "$type": .string("app.bsky.richtext.facet#link"),
                    "uri": .string(link.url),
                ]
            )
        })
        facets.append(contentsOf: tags.map { tag in
            facet(
                range: tag.range,
                feature: [
                    "$type": .string("app.bsky.richtext.facet#tag"),
                    "tag": .string(tag.tag),
                ]
            )
        })
        facets.sort {
            (facetByteRange($0)?.lowerBound ?? Int.max) <
                (facetByteRange($1)?.lowerBound ?? Int.max)
        }
        return facets.isEmpty ? nil : facets
    }

    public static func normalizeEmbed(_ embed: JSONValue?) -> JSONValue? {
        guard case let .object(object) = embed else {
            return embed
        }
        if object["$type"] != nil {
            return embed
        }
        guard case let .object(external)? = object["external"],
              case let .string(uri)? = external["uri"]
        else {
            return embed
        }
        var normalizedExternal = external
        if normalizedExternal["title"] == nil {
            normalizedExternal["title"] = .string(URL(string: uri)?.host ?? uri)
        }
        if normalizedExternal["description"] == nil {
            normalizedExternal["description"] = .string("")
        }
        return .object([
            "$type": .string("app.bsky.embed.external"),
            "external": .object(normalizedExternal),
        ])
    }

    private static func detectedLinks(in text: String) -> [(url: String, range: Range<Int>)] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return urlExpression.matches(in: text, range: fullRange).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }
            let candidate = String(text[matchRange])
            let trimmed = trimTrailingPunctuation(candidate)
            guard !trimmed.isEmpty,
                  let components = URLComponents(string: trimmed),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host != nil
            else {
                return nil
            }
            let end = text.index(matchRange.lowerBound, offsetBy: trimmed.count)
            let byteStart = text[..<matchRange.lowerBound].utf8.count
            let byteEnd = byteStart + text[matchRange.lowerBound..<end].utf8.count
            return (trimmed, byteStart..<byteEnd)
        }
    }

    private static func detectedTags(in text: String) -> [(tag: String, range: Range<Int>)] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return tagExpression.matches(in: text, range: fullRange).compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            // The capture keeps the leading "#", which the facet range covers but the
            // tag value omits.
            let body = trimTrailingTagPunctuation(text[matchRange].dropFirst())
            guard !body.isEmpty, body.utf16.count <= maxTagLength else {
                return nil
            }
            let byteStart = text[..<matchRange.lowerBound].utf8.count
            let byteEnd = byteStart + text[matchRange.lowerBound..<body.endIndex].utf8.count
            return (String(body), byteStart..<byteEnd)
        }
    }

    private static func trimTrailingTagPunctuation(_ value: Substring) -> Substring {
        var result = value
        while let last = result.last,
              last.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
        {
            result = result.dropLast()
        }
        return result
    }

    private static func trimTrailingPunctuation(_ value: String) -> String {
        var result = value
        while let scalar = result.unicodeScalars.last,
              simpleTrailingPunctuation.contains(scalar)
        {
            result.removeLast()
        }
        var changed = true
        while changed {
            changed = false
            for (open, close) in closingPairs where result.last == close {
                let openCount = result.lazy.filter { $0 == open }.count
                let closeCount = result.lazy.filter { $0 == close }.count
                if closeCount > openCount {
                    result.removeLast()
                    changed = true
                }
            }
        }
        return result
    }

    private static func facet(range: Range<Int>, feature: [String: JSONValue]) -> JSONValue {
        .object([
            "index": .object([
                "byteStart": .number(Double(range.lowerBound)),
                "byteEnd": .number(Double(range.upperBound)),
            ]),
            "features": .array([.object(feature)]),
        ])
    }

    /// Link and tag facets are always regenerated from the text, so stale copies sent by
    /// a client are dropped instead of preserved.
    private static func facetContainsGeneratedFeature(_ facet: JSONValue) -> Bool {
        guard case let .object(object) = facet,
              case let .array(features)? = object["features"]
        else {
            return false
        }
        return features.contains { feature in
            guard case let .object(object) = feature,
                  case let .string(type)? = object["$type"]
            else {
                return false
            }
            return type == "app.bsky.richtext.facet#link" ||
                type == "app.bsky.richtext.facet#tag"
        }
    }

    private static func facetByteRange(_ facet: JSONValue) -> Range<Int>? {
        guard case let .object(object) = facet,
              case let .object(index)? = object["index"],
              case let .number(start)? = index["byteStart"],
              case let .number(end)? = index["byteEnd"]
        else {
            return nil
        }
        return Int(start)..<Int(end)
    }
}
