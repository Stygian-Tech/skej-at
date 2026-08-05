import Foundation
@testable import SkejKit
import Testing

@Suite
struct ATProtoTIDTests {
    @Test func generatesValidSortableTIDs() {
        let date = ISO8601DateFormatter().date(from: "2026-01-01T10:00:00Z")!
        let first = ATProtoTID.generate(date: date)
        let second = ATProtoTID.generate(date: date)

        #expect(ATProtoTID.isValid(first))
        #expect(ATProtoTID.isValid(second))
        #expect(first.count == 13)
        #expect(second > first)
    }

    @Test func rejectsULIDsAndMalformedTIDs() {
        #expect(!ATProtoTID.isValid("01KZ7M5Z3M6D4TZS9F67ESBWC1"))
        #expect(!ATProtoTID.isValid("3JZFCIJPJ2Z2A"))
        #expect(!ATProtoTID.isValid("3jzfcijpj2z21"))
        #expect(ATProtoTID.isValid("3jzfcijpj2z2a"))
    }
}
