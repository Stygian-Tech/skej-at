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
env DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run SkejAPI
```

