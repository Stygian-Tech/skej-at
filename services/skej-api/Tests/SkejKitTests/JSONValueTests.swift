import Foundation
import SkejKit
import Testing

@Suite
struct JSONValueTests {
    @Test func modelConversionPreservesNumbersAndBooleans() throws {
        struct Payload: Encodable {
            let zero = 0
            let one = 1
            let enabled = true
        }

        let value = try Payload().skejJSONValue()

        guard case let .object(object) = value else {
            Issue.record("Expected an object")
            return
        }
        #expect(object["zero"] == .number(0))
        #expect(object["one"] == .number(1))
        #expect(object["enabled"] == .bool(true))
    }

    @Test func foundationObjectConversionDistinguishesNumbersFromBooleans() throws {
        let object = try JSONSerialization.jsonObject(
            with: Data(#"{"zero":0,"one":1,"enabled":true}"#.utf8)
        )
        let value = try makeJSONValue(from: object)

        guard case let .object(object) = value else {
            Issue.record("Expected an object")
            return
        }
        #expect(object["zero"] == .number(0))
        #expect(object["one"] == .number(1))
        #expect(object["enabled"] == .bool(true))
    }

    @Test func scheduleRetryNumbersRemainNumbersForPDSWrites() throws {
        let record = SkejScheduleRecord(
            scheduledAt: "2026-07-30T05:00:00Z",
            createdAt: "2026-07-30T04:00:00Z",
            updatedAt: "2026-07-30T04:00:00Z",
            status: .scheduled,
            publishRkey: "test",
            retry: RetryState(attemptCount: 0, maxAttempts: 8),
            posts: [PostPlan(text: "Hello")]
        )

        let value = try record.skejJSONValue()

        guard case let .object(recordObject) = value,
              case let .object(retry)? = recordObject["retry"]
        else {
            Issue.record("Expected a schedule retry object")
            return
        }
        #expect(retry["attemptCount"] == .number(0))
        #expect(retry["maxAttempts"] == .number(8))
    }

    @Test func retryStateDecodesLegacyBooleanAttemptCounts() throws {
        let falseRetry = try JSONDecoder().decode(
            RetryState.self,
            from: Data(#"{"attemptCount":false,"maxAttempts":8}"#.utf8)
        )
        let trueRetry = try JSONDecoder().decode(
            RetryState.self,
            from: Data(#"{"attemptCount":true,"maxAttempts":8}"#.utf8)
        )

        #expect(falseRetry.attemptCount == 0)
        #expect(trueRetry.attemptCount == 1)
        #expect(falseRetry.maxAttempts == 8)
    }
}
