# Railway deployment configuration

Railway is the canonical gateway host for Development and Production. GitHub
Actions validates source changes; Railway deploys the linked branch through its
GitHub integration.

The `Gateway` service keeps the monorepo root directory at `/` and uses
`/railway/gateway.json`. Development tracks `dev`; Production tracks `main`.

Each environment has its own persistent volume mounted at
`/var/lib/skej-api/data`. The service must remain at one replica because SQLite
and the in-process schedule worker share that volume. `overlapSeconds` is zero
to prevent two worker revisions from running against the database during a
deployment.
