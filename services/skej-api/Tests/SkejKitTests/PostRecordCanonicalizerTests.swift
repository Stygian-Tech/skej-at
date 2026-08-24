import Foundation
import SkejKit
import Testing

@Suite
struct PostRecordCanonicalizerTests {
    @Test func markdownSourceAuthoritativelyRebuildsProjectionAndLabeledLinkFacet() {
        let staleLink: JSONValue = .object([
            "index": .object(["byteStart": .number(0), "byteEnd": .number(4)]),
            "features": .array([.object([
                "$type": .string("app.bsky.richtext.facet#link"),
                "uri": .string("https://stale.invalid"),
            ])]),
        ])

        let canonical = PostRecordCanonicalizer.canonicalize(PostPlan(
            text: "stale projection",
            source: PostSource(format: .markdown, text: "👋 [Skej](https://skej.at)"),
            publishRkey: "3aaaaaaaaaaaa",
            facets: [staleLink],
            unknownFields: ["future": .string("preserved")]
        ))

        #expect(canonical.text == "👋 Skej")
        #expect(canonical.source?.text == "👋 [Skej](https://skej.at)")
        #expect(canonical.publishRkey == "3aaaaaaaaaaaa")
        #expect(canonical.unknownFields["future"] == .string("preserved"))
        #expect(canonical.facets?.count == 1)
        #expect(byteRange(canonical.facets?.first) == 5..<9)
        #expect(linkURI(canonical.facets?.first) == "https://skej.at")
    }

    @Test func markdownExcludedBlocksDoNotRegainAutomaticFacetsDuringCanonicalization() {
        let canonical = PostRecordCanonicalizer.canonicalize(PostPlan(
            text: "stale",
            source: PostSource(
                format: .markdown,
                text: "# Literal https://example.com #heading\n```\nhttps://inside.example #code\n```"
            )
        ))

        #expect(canonical.text.contains("https://example.com"))
        #expect(canonical.facets == nil)
    }

    @Test func detectsMultipleURLsWithUTF8ByteOffsetsAndPunctuation() throws {
        let text = "👋 https://example.com, then (https://bsky.app)."
        let facets = PostRecordCanonicalizer.facets(in: text)

        #expect(facets?.count == 2)
        #expect(byteRange(facets?[0]) == 5..<24)
        #expect(linkURI(facets?[0]) == "https://example.com")
        #expect(linkURI(facets?[1]) == "https://bsky.app")
        #expect(byteRange(facets?[1]) == 32..<48)
    }

    @Test func preservesValidNonLinkFacetsAndReplacesLinkFacets() throws {
        let mention: JSONValue = .object([
            "index": .object([
                "byteStart": .number(0),
                "byteEnd": .number(4),
            ]),
            "features": .array([
                .object([
                    "$type": .string("app.bsky.richtext.facet#mention"),
                    "did": .string("did:plc:test"),
                ]),
            ]),
        ])
        let staleLink: JSONValue = .object([
            "index": .object([
                "byteStart": .number(5),
                "byteEnd": .number(8),
            ]),
            "features": .array([
                .object([
                    "$type": .string("app.bsky.richtext.facet#link"),
                    "uri": .string("https://stale.invalid"),
                ]),
            ]),
        ])

        let facets = PostRecordCanonicalizer.facets(
            in: "@sam https://example.com",
            preserving: [staleLink, mention]
        )

        #expect(facets?.count == 2)
        #expect(mentionDID(facets?[0]) == "did:plc:test")
        #expect(linkURI(facets?[1]) == "https://example.com")
    }

    @Test func dropsPreservedFacetsThatOverlapDetectedLinks() {
        let overlap: JSONValue = .object([
            "index": .object([
                "byteStart": .number(8),
                "byteEnd": .number(12),
            ]),
            "features": .array([
                .object([
                    "$type": .string("app.bsky.richtext.facet#mention"),
                    "did": .string("did:plc:test"),
                ]),
            ]),
        ])

        let facets = PostRecordCanonicalizer.facets(
            in: "read https://example.com",
            preserving: [overlap]
        )

        #expect(facets?.count == 1)
        #expect(linkURI(facets?[0]) == "https://example.com")
    }

    @Test func dropsStaleMentionFacetsThatNoLongerCoverAMention() {
        let staleMention: JSONValue = .object([
            "index": .object([
                "byteStart": .number(0),
                "byteEnd": .number(4),
            ]),
            "features": .array([
                .object([
                    "$type": .string("app.bsky.richtext.facet#mention"),
                    "did": .string("did:plc:test"),
                ]),
            ]),
        ])

        #expect(PostRecordCanonicalizer.facets(in: "Skej", preserving: [staleMention]) == nil)
    }

    @Test func detectsTagsWithUTF8ByteOffsetsAndTrailingPunctuation() {
        let text = "👋 #skej and #dev, not #123 or mid#word"
        let facets = PostRecordCanonicalizer.facets(in: text)

        #expect(facets?.count == 2)
        #expect(tagValue(facets?[0]) == "skej")
        #expect(byteRange(facets?[0]) == 5..<10)
        #expect(tagValue(facets?[1]) == "dev")
        #expect(byteRange(facets?[1]) == 15..<19)
    }

    @Test func ordersTagAndLinkFacetsTogetherAndSkipsURLFragments() {
        let facets = PostRecordCanonicalizer.facets(
            in: "#skej https://example.com/docs#anchor #done"
        )

        #expect(facets?.count == 3)
        #expect(tagValue(facets?[0]) == "skej")
        #expect(linkURI(facets?[1]) == "https://example.com/docs#anchor")
        #expect(tagValue(facets?[2]) == "done")
    }

    @Test func skipsOverlongTagsAndReplacesStaleTagFacets() {
        let stale: JSONValue = .object([
            "index": .object([
                "byteStart": .number(40),
                "byteEnd": .number(44),
            ]),
            "features": .array([
                .object([
                    "$type": .string("app.bsky.richtext.facet#tag"),
                    "tag": .string("stale"),
                ]),
            ]),
        ])
        let overlong = String(repeating: "a", count: 65)

        let facets = PostRecordCanonicalizer.facets(
            in: "#\(overlong) #ok",
            preserving: [stale]
        )

        #expect(facets?.count == 1)
        #expect(tagValue(facets?[0]) == "ok")
    }

    @Test func ignoresMalformedURLsAndKeepsBalancedParentheses() {
        let facets = PostRecordCanonicalizer.facets(
            in: "bad http:// and good https://example.com/docs_(v2))."
        )

        #expect(facets?.count == 1)
        #expect(linkURI(facets?[0]) == "https://example.com/docs_(v2)")
    }

    @Test func normalizesLegacyExternalEmbedAndBuildsExactFeedRecord() throws {
        let legacyEmbed: JSONValue = .object([
            "external": .object([
                "uri": .string("https://example.com"),
                "title": .string("Example"),
            ]),
        ])
        let post = try PostRecordCanonicalizer.feedPostValue(
            PostPlan(text: "Read https://example.com", embed: legacyEmbed),
            createdAt: "2026-07-29T12:00:00Z"
        )

        guard case let .object(embed)? = post["embed"],
              case let .string(type)? = embed["$type"],
              case let .object(external)? = embed["external"],
              case let .string(description)? = external["description"]
        else {
            Issue.record("Expected a typed external embed")
            return
        }
        #expect(type == "app.bsky.embed.external")
        #expect(description == "")
        guard case let .array(facets)? = post["facets"] else {
            Issue.record("Expected generated link facets")
            return
        }
        #expect(linkURI(facets.first) == "https://example.com")
        #expect(byteRange(facets.first) == 5..<24)
    }

    @Test func repairsAlreadyScheduledShadowRecordsBeforePublishing() {
        let repaired = PostRecordCanonicalizer.canonicalizeFeedPost(.object([
            "$type": .string("app.bsky.feed.post"),
            "text": .string("Saved earlier https://example.com"),
            "embed": .object([
                "external": .object([
                    "uri": .string("https://example.com"),
                    "title": .string("Example"),
                    "description": .string("Description"),
                ]),
            ]),
        ]))

        guard case let .object(post) = repaired,
              case let .array(facets)? = post["facets"],
              case let .object(embed)? = post["embed"],
              case let .string(type)? = embed["$type"]
        else {
            Issue.record("Expected a repaired feed record")
            return
        }
        #expect(linkURI(facets.first) == "https://example.com")
        #expect(type == "app.bsky.embed.external")
    }

    private func byteRange(_ facet: JSONValue?) -> Range<Int>? {
        guard case let .object(object)? = facet,
              case let .object(index)? = object["index"],
              case let .number(start)? = index["byteStart"],
              case let .number(end)? = index["byteEnd"]
        else {
            return nil
        }
        return Int(start)..<Int(end)
    }

    private func linkURI(_ facet: JSONValue?) -> String? {
        featureValue(facet, type: "app.bsky.richtext.facet#link", key: "uri")
    }

    private func mentionDID(_ facet: JSONValue?) -> String? {
        featureValue(facet, type: "app.bsky.richtext.facet#mention", key: "did")
    }

    private func tagValue(_ facet: JSONValue?) -> String? {
        featureValue(facet, type: "app.bsky.richtext.facet#tag", key: "tag")
    }

    private func featureValue(_ facet: JSONValue?, type: String, key: String) -> String? {
        guard case let .object(object)? = facet,
              case let .array(features)? = object["features"]
        else {
            return nil
        }
        for feature in features {
            guard case let .object(value) = feature,
                  case let .string(featureType)? = value["$type"],
                  featureType == type,
                  case let .string(result)? = value[key]
            else {
                continue
            }
            return result
        }
        return nil
    }
}
