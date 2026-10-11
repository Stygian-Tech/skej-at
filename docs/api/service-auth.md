# Account-Bound Scheduling API

Other AT Protocol clients can schedule posts through Skej without changing their
current browser account. Skej stores `at.skej.schedule` records on the selected
account's PDS and its existing worker publishes them while the client is closed.
The account must first complete Skej's OAuth sign-in so the worker has usable
server-side credentials. A service token authorizes a request; it does not supply
those credentials or grant access to another account.

## Discovery and Authentication

Public `GET /.well-known/did.json` exposes the API hostname's `did:web` identity
and service `#skej_scheduler` of type `SkejScheduler`. The service endpoint is the
HTTPS API origin. Hosted audiences are:

- Development: `did:web:api.testing.skej.at#skej_scheduler`
- Production: `did:web:api.skej.at#skej_scheduler`

Obtain a fresh token from the selected account's PDS with OAuth-authenticated
`com.atproto.server.getServiceAuth`, using the discovered service audience as
`aud`, the exact endpoint NSID as `lxm`, and expiry at most 60 seconds away. Send
that token as `Authorization: Bearer <token>` to Skej. Do not forward the PDS
OAuth access token, share browser cookies, or persist these service tokens.

Skej verifies the issuer's AT Protocol signing key, audience, method, issue and
expiry times, and `jti`. Replay protection persists in Skej's SQLite store. Each
request, including a retry, needs a fresh token. Supported signatures are ES256
and ES256K. Optional JWT `kid` must be `#atproto`.

## Supported Routes

Only these existing XRPC methods accept service authentication. Input/output
schemas remain the canonical JSON Lexicons in `packages/lexicons`.

| Method | Path | Input | Output |
| --- | --- | --- | --- |
| GET | `/xrpc/at.skej.actor.getSession` | No parameters | `at.skej.defs#viewer` |
| GET | `/xrpc/at.skej.schedule.list` | Optional `accountDid` query parameter | `{ "records": [at.skej.defs#scheduleSummary] }` |
| POST | `/xrpc/at.skej.schedule.create` | `{ "accountDid"?: DID, "record": at.skej.schedule }` | `at.skej.defs#scheduleSummary` |
| POST | `/xrpc/at.skej.schedule.update` | `{ "accountDid"?: DID, "rkey": string, "record": at.skej.schedule }` | `at.skej.defs#scheduleSummary` |
| POST | `/xrpc/at.skej.schedule.cancel` | `{ "accountDid"?: DID, "rkey": string }` | `at.skej.defs#scheduleSummary` |

Procedure bodies use `Content-Type: application/json`. Omitted `accountDid`
selects the token's issuer; any supplied account must equal `iss`. Team or admin
membership cannot widen this boundary. A bearer token on another route is
rejected, including `publishNow`, team APIs, and legacy `/v1` routes. Existing
cookie-authenticated flows remain available independently.

A create request uses `status: "scheduled"`, an absolute UTC `scheduledAt`, and
a stable `publishRkey` for publication identity. Preserve the returned record
when updating; change its timestamp and `updatedAt`, and set status to
`scheduled` when rescheduling. The PDS record remains authoritative. Only
`draft`, `scheduled`, `blocked`, and `failed` schedules are editable; worker leases,
and already publishing/published/canceled schedules prevent updates and
cancellation. Edit leases prevent an API edit from racing the local worker;
this is not an expected-CID guard against arbitrary cross-device edits.

## Errors and Recovery

Errors retain the XRPC shape `{ "error": "Name", "message": "Detail" }`.

| HTTP | Error | Recovery |
| --- | --- | --- |
| 401 | `InvalidServiceAuth` | Obtain a fresh method/audience-bound token; check discovery and expiry. |
| 403 | `ActorMismatch` | Use the same account for the token issuer and request. |
| 409 | `AccountNeedsReauth` | Sign the selected account into Skej again. Missing/corrupt Skej OAuth credentials cannot be supplied by service auth. |
| 409 | `account_needs_reauth` | The account's existing PDS credentials were revoked; reconnect it in Skej. |
| 409 | `ScheduleNotEditable` | Reload the schedule; it is leased, publishing, or finished. Do not retry an edit blindly. |
| 409 | `ScheduleChanged` | The authoritative schedule is missing. Reload before editing. |

GET `actor.getSession` is the readiness check. Its returned viewer DID must equal
the selected account. Show a connection action for reauthorization responses,
without treating an unavailable service or invalid token as an empty calendar.

After the normal Skej OAuth flow, `/scheduling/connected` provides a compact
connection confirmation. It requires Skej cookie authentication and a usable
server-side grant; it returns no credentials or account identity. Set
`returnTo=/scheduling/connected` when starting the connection flow.

## Configuration

`SKEJ_API_ORIGIN` specifies the HTTPS API origin used by the public service DID
and audience. This is independent of `SKEJ_PUBLIC_ORIGIN`, which continues to own
Skej's existing OAuth client metadata. Existing worker and persistent SQLite
configuration remains required; this API does not create another scheduler.
Live OAuth storage requires `SKEJ_AUTH_ENCRYPTION_KEY`. Keep this stable secret in
the service environment, outside the repository. Startup validates existing
ciphertext, transactionally encrypts legacy session and pending OAuth secrets,
and compacts/truncates SQLite and its WAL before serving requests. A missing or
wrong key fails closed; do not rotate it without a separate migration. Volume
snapshots and historical backups may still contain older plaintext and need
their existing retention controls.
`SKEJ_CORS_ORIGINS` can admit additional exact HTTPS browser origins. Hosted
defaults include the corresponding Skej and Social Wire web origins; local
defaults include loopback Social Wire on port 3016.

PLC account keys resolve through the PLC directory. DID-web issuer origins must
be explicitly admitted by `SKEJ_DID_WEB_ORIGINS`. Local sandbox overrides apply
only with `APP_ENV=local`: `SKEJ_LOCAL_PLC_ORIGIN`,
`SKEJ_LOCAL_HANDLE_RESOLVER_ORIGIN`, `SKEJ_LOCAL_PDS_ORIGINS`, and
`SKEJ_LOCAL_DID_WEB_ORIGINS`. Use exact HTTPS origins with the sandbox CA trusted;
local admission does not disable TLS verification.

The repository uses Lexicons and typed SkejKit XRPC contracts rather than an
OpenAPI or Bruno collection. Contract tests verify this documented route set
against the gateway's service-auth route boundary and Lexicon error declarations.
