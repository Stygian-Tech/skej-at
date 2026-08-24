# Skej

Skej is an AT Protocol post scheduler. Users sign in with their PDS, create full Bluesky-style posts, and store scheduled content in their own PDS under the `at.skej.schedule` lexicon until the Swift worker publishes it.

## Layout

- `apps/web`: Next.js App Router UI.
- `packages/skej-kit`: reusable Swift 6 scheduling, PDS, worker, and typed XRPC client package.
- `services/skej-api`: thin Hummingbird OAuth/session host (`SkejGateway`) and executable.
- `packages/lexicons`: AT Protocol lexicon JSON.

## XRPC API

Product operations are defined by Lexicons and exposed at top-level
`/xrpc/{NSID}` routes. Queries use `GET` with declared query parameters;
procedures use `POST` with `application/json` input. Errors use the standard
`{"error":"Name","message":"Human-readable detail"}` shape.

Examples:

```text
GET  /xrpc/at.skej.schedule.list?accountDid=did:plc:example
POST /xrpc/at.skej.schedule.create
POST /xrpc/at.skej.schedule.publishNow
GET  /xrpc/at.skej.team.list
```

Health checks and OAuth metadata/start/callback routes remain ordinary HTTP
because they are infrastructure or OAuth protocol endpoints, not XRPC methods.
The legacy `/v1` surface remains temporarily as a compatibility adapter; the
web app and new consumers use XRPC.

## Local Development

```bash
bun install
bun run dev
```

Run the Swift API separately:

```bash
cd services/skej-api
swift run SkejAPI
```

## Environment

Hosted dev OAuth follows the same pattern as the other ATProto apps: the public
gateway serves client metadata from an unprotected API origin, while redirect
URIs point back at the browser-facing web origin.

Local defaults:

```bash
# apps/web/.env.local
SKEJ_API_URL=http://127.0.0.1:8080
APP_ENV=local
NEXT_PUBLIC_APP_ENV=local
NEXT_PUBLIC_SITE_URL=http://127.0.0.1:3000

# services/skej-api/.env.local
APP_ENV=local
PORT=8080
SKEJ_PUBLIC_ORIGIN=http://127.0.0.1:8080
SKEJ_WEB_ORIGIN=http://127.0.0.1:3000
SKEJ_SQLITE_PATH=data/skej.sqlite
SKEJ_WORKER_ENABLED=true
SKEJ_WORKER_INTERVAL_SECONDS=30
SKEJ_LIVE_ATPROTO_ENABLED=false
SKEJ_PRO_ENABLED=true
```

`SKEJ_PRO_ENABLED` gates the Skej Pro features (teams, calendar, approvals,
posting on behalf of other accounts). It defaults to on everywhere except
prod; when off, the Pro API routes are not registered at all.

Hosted defaults:

| Target | Web Origin | API Origin | Banner | OAuth Callback |
| --- | --- | --- | --- | --- |
| Local | `http://127.0.0.1:3000` | `http://127.0.0.1:8080` | `local` | `http://127.0.0.1:3000/oauth/callback` |
| Dev | `https://testing.skej.at` | `https://api.testing.skej.at` | `dev` | `https://testing.skej.at/oauth/callback` |
| Prod | `https://skej.at` | `https://api.skej.at` | `prod` | `https://skej.at/oauth/callback` |

Required hosted web variables:

```bash
SKEJ_API_URL=https://api.testing.skej.at # dev
APP_ENV=dev
NEXT_PUBLIC_APP_ENV=dev
NEXT_PUBLIC_SITE_URL=https://testing.skej.at
```

```bash
SKEJ_API_URL=https://api.skej.at # prod
APP_ENV=prod
NEXT_PUBLIC_APP_ENV=prod
NEXT_PUBLIC_SITE_URL=https://skej.at
```

Required hosted gateway variables:

```bash
APP_ENV=dev
SKEJ_PUBLIC_ORIGIN=https://api.testing.skej.at
SKEJ_WEB_ORIGIN=https://testing.skej.at
SKEJ_PRO_ENABLED=true
```

```bash
APP_ENV=prod
SKEJ_PUBLIC_ORIGIN=https://skej.at
SKEJ_PRO_ENABLED=false
```

## CI

GitHub Actions runs:

- `scripts/ci-js.sh` for Bun install, linting, typechecking, tests, and Next builds.
- `scripts/ci-swift.sh` for Swift tests and release builds.
- A gateway Docker build when `services/skej-api` or deployment files change.

Run the same checks locally:

```bash
bash scripts/ci.sh
```

## Railway Hosting

Railway hosts the Next.js web app and Swift gateway in isolated `dev` and
`production` environments. Each environment has one stateless `Web` replica
and one `Gateway` replica with its own persistent SQLite volume mounted at
`/var/lib/skej-api/data`.

Railway deploys `dev` from the `dev` branch and Production from `main` using
`railway/web.json` and `railway/gateway.json`. GitHub Actions remains the
required source validation pipeline and does not deploy infrastructure.

See [Railway gateway migration and operations](docs/deployment/railway.md) for
environment variables, SQLite migration, verification, and ongoing operations.
