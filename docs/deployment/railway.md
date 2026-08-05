# Railway gateway migration and operations

Railway hosts the Next.js web app and Swift gateway in one project with
isolated `dev` and `production` environments.

| Environment | Branch | Web origin | Gateway domain | SQLite volume |
| --- | --- | --- | --- | --- |
| Development | `dev` | `https://testing.skej.at` | `https://api.testing.skej.at` | Development-only |
| Production | `main` | `https://skej.at` | `https://api.skej.at` | Production-only |

## Service configuration

The stateless `Web` service uses `/railway/web.json`, listens on port 3000, and
sets the hosted web variables from the root README for its environment. It does
not mount a volume.

The `Gateway` service uses `/railway/gateway.json` from the repository root and
must run exactly one replica. Configure these variables in each environment:

```bash
PORT=8080
SKEJ_SQLITE_PATH=/var/lib/skej-api/data/skej.sqlite
SKEJ_WORKER_ENABLED=true
SKEJ_WORKER_INTERVAL_SECONDS=30
SKEJ_LIVE_ATPROTO_ENABLED=true
RAILWAY_RUN_UID=0
```

Development also uses:

```bash
APP_ENV=dev
SKEJ_PUBLIC_ORIGIN=https://api.testing.skej.at
SKEJ_WEB_ORIGIN=https://testing.skej.at
```

Production preserves the existing OAuth client identity while changing the
gateway host:

```bash
APP_ENV=prod
SKEJ_PUBLIC_ORIGIN=https://skej.at
SKEJ_WEB_ORIGIN=https://skej.at
```

`RAILWAY_RUN_UID=0` is required because Railway mounts volumes as root while the
container image normally runs as `nobody`. The volume mount is available only
at runtime, so SQLite migrations stay in application startup rather than a
pre-deploy command.

## SQLite migration

The completed migration used this sequence for each environment:

1. Disable the worker on Fly and stop the source machine.
2. Copy the quiescent SQLite file and verify `PRAGMA integrity_check` locally.
3. Upload the database to the environment-local Railway volume before enabling
   its worker.
4. Verify table counts and database integrity on Railway.
5. Start the Railway service, verify health and OAuth metadata, and then move
   the gateway DNS record.
6. Exercise sign-in, schedule creation, rich-link publishing, and persistence
   across a Railway restart.

The former Fly apps and volumes have been removed. Railway is now the system of
record for both SQLite databases. Before copying or restoring a database, stop
the environment's worker and verify `PRAGMA integrity_check`; never run two
workers against independently writable copies of the same environment.
