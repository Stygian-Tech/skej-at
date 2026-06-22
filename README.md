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

## CI

GitHub Actions runs:

- `scripts/ci-js.sh` for Bun install, linting, typechecking, tests, and Next builds.
- `scripts/ci-swift.sh` for Swift tests and release builds with warnings as errors.
- A gateway Docker build when `services/skej-api` or deployment files change.

Run the same checks locally:

```bash
bash scripts/ci.sh
```

## Fly Gateway

The Swift gateway is configured for Fly in `services/skej-api/fly.toml`.

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
