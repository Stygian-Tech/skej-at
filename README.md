# Skej

Skej is an AT Protocol post scheduler. Users sign in with their PDS, create full Bluesky-style posts, and store scheduled content in their own PDS under the `at.skej.schedule` lexicon until the Swift worker publishes it.

## Layout

- `apps/web`: Next.js App Router UI.
- `services/skej-api`: Swift 6 Hummingbird API and always-on worker.
- `packages/lexicons`: AT Protocol lexicon JSON.

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

The OAuth public origin must be the browser-facing web origin because the web app
proxies `/oauth/*` to the Swift gateway. That origin is what ATProto sees in
`/oauth/client-metadata.json` and where providers redirect after authorization.

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
SKEJ_PUBLIC_ORIGIN=http://127.0.0.1:3000
SKEJ_SQLITE_PATH=data/skej.sqlite
SKEJ_WORKER_ENABLED=true
SKEJ_WORKER_INTERVAL_SECONDS=30
SKEJ_LIVE_ATPROTO_ENABLED=false
```

Hosted defaults:

| Target | Web Origin | API Origin | Banner | OAuth Callback |
| --- | --- | --- | --- | --- |
| Local | `http://127.0.0.1:3000` | `http://127.0.0.1:8080` | `local` | `http://127.0.0.1:3000/oauth/callback` |
| Dev | `https://testing.skej.at` | `https://skej-at-dev-gateway.fly.dev` | `dev` | `https://testing.skej.at/oauth/callback` |
| Prod | `https://skej.at` | `https://skej-at-prod-gateway.fly.dev` | `prod` | `https://skej.at/oauth/callback` |

Required hosted web variables:

```bash
SKEJ_API_URL=https://skej-at-dev-gateway.fly.dev # dev
APP_ENV=dev
NEXT_PUBLIC_APP_ENV=dev
NEXT_PUBLIC_SITE_URL=https://testing.skej.at
```

```bash
SKEJ_API_URL=https://skej-at-prod-gateway.fly.dev # prod
APP_ENV=prod
NEXT_PUBLIC_APP_ENV=prod
NEXT_PUBLIC_SITE_URL=https://skej.at
```

Required hosted gateway variables:

```bash
APP_ENV=dev
SKEJ_PUBLIC_ORIGIN=https://testing.skej.at
```

```bash
APP_ENV=prod
SKEJ_PUBLIC_ORIGIN=https://skej.at
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

## Fly Gateway

The Swift gateway is configured for Fly in `services/skej-api/fly.toml`.
The Dockerfile is service-local; in the Fly web UI, set the source/root directory
to `services/skej-api`.

Default app names:

- Dev: `skej-at-dev-gateway`
- Prod: `skej-at-prod-gateway`

Create the persistent SQLite volume once per app before deploying:

```bash
fly volumes create skej_api_data --app skej-at-dev-gateway --region ams --size 1
fly volumes create skej_api_data --app skej-at-prod-gateway --region ams --size 1
```

Deploy manually:

```bash
bash services/skej-api/deploy.sh dev
bash services/skej-api/deploy.sh main
```

CI deploys on `main` and `dev` pushes when gateway files change, or by manual workflow dispatch with `deploy_gateway=true`.

Required GitHub secret:

- `FLY_API_TOKEN`

Optional GitHub secrets:

- `FLY_SKEJ_GATEWAY_APP_DEV`
- `FLY_SKEJ_GATEWAY_APP_PROD`
- `SKEJ_PUBLIC_ORIGIN_DEV`
- `SKEJ_PUBLIC_ORIGIN_PROD`
