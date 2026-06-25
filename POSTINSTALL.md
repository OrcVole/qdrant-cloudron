Qdrant is running and ready. There is no setup wizard: get your API key below, then point your apps
or your code at Qdrant whenever you want to use it. Opening the dashboard is optional.

### 1. Get your API key

Open a Terminal for this app (the `>_` button at the top of this page) and run:

    cat /app/data/.secrets/keys.env

It prints two keys: `QDRANT_ADMIN_API_KEY` (full access) and `QDRANT_READONLY_API_KEY` (read only).
You give one of these keys to anything that connects to Qdrant.

### 2. Open the dashboard (optional)

Open $CLOUDRON-APP-ORIGIN/dashboard, sign in with your Cloudron account, and paste the admin key into
the API key field to browse and manage your collections.

## How other apps and code connect to Qdrant

You do not need to run anything here to finish setup; Qdrant is ready. This just explains how to
reach it from elsewhere when you want to use it.

- **From another Cloudron app** (n8n, OpenWebUI, AnythingLLM, and so on): in that other app's own
  settings, set the Qdrant URL to $CLOUDRON-APP-ORIGIN and paste an API key. This is configured in
  the other app, not here. See `docs/INTEGRATIONS.md` for per-app recipes.
- **From your own code or scripts:** connect over REST at $CLOUDRON-APP-ORIGIN with the key. For
  high-throughput Rust clients (`rig-qdrant`), use gRPC at the host and port shown under this app's
  Location settings (it is plain TCP, not TLS-terminated; see the README security section).

Optional: to confirm the key works, run this **from your own computer** (for example a terminal on
your laptop, not this app's Terminal). It returns a JSON list of your collections:

    curl $CLOUDRON-APP-ORIGIN/collections -H "api-key: PASTE-ADMIN-KEY-HERE"

### More

- **Scoped tokens:** JWT and RBAC are on. Mint read-only or per-collection tokens in the dashboard's
  Access Tokens panel; rotating the admin key revokes them all.
- **Memory:** the limit is 2 GB. Qdrant rejects writes (while still serving reads) near the limit
  rather than being killed. For large collections, raise the limit, store vectors on disk, or use
  TurboQuant.
- Full topology, security, and integration recipes are in the README and `docs/INTEGRATIONS.md`.
