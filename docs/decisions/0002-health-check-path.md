# 0002: Health check on /healthz, not /readyz

Status: accepted (verified on a live box, 2026-06-25)

## Context

Cloudron polls healthCheckPath on the primary httpPort and expects a 2xx response. A non-2xx marks
the app unhealthy and the platform restarts it. Qdrant exposes three unauthenticated endpoints:
/livez and /healthz return 200 as soon as the HTTP listener binds, while /readyz returns 503 until
all shards are loaded and ready.

## Decision

Use healthCheckPath = /healthz.

A vector database can take time to load large collections on start. If the health check used
/readyz, Cloudron would see 503 during that load and restart the app, which on a slow or
memory-pressured load could become a restart loop, the exact failure mode this package is designed
to avoid. /healthz reports healthy as soon as the server is serving, which is the right signal for
"should the platform leave this app running". True readiness remains available to clients at
/readyz.

/healthz is not under /dashboard, so the proxyAuth wall does not cover it, and it bypasses the API
key, so the platform health check needs no credential. Cloudron's health check also reaches the
container directly rather than through the public proxy.

## Consequences

- The app is reported healthy when it is serving, which avoids a restart loop during a long
  collection load.
- Clients that need to know the database is fully ready use /readyz themselves.
- If a future Qdrant release changes these endpoints, re-verify and update this decision and the
  manifest (recorded in docs/UPGRADING.md).
