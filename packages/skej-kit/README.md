# SkejKit

Reusable Swift scheduling and XRPC client library for Skej.

SkejKit owns the `at.skej.schedule` domain model, schedule persistence and PDS
abstractions, the publishing worker, Bluesky post canonicalization, link preview
hydration, and the typed contracts used by the Skej XRPC service. HTTP hosting,
OAuth callbacks, and browser session policy remain in `SkejGateway`.

The package supports Swift 6 on macOS 14+, iOS 17+, and Linux.

```swift
import SkejKit

let client = SkejXRPCClient(transport: transport)
let schedules = try await client.listSchedules(.init(accountDid: nil))
```
