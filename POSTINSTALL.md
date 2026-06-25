### Qdrant is running and ready

No setup wizard. Get your API key below, then point your apps or your code at Qdrant whenever you
want. The dashboard is optional.

**Get your API key.** Open this app's Terminal (the `>_` button above) and run
`cat /app/data/.secrets/keys.env`. It prints `QDRANT_ADMIN_API_KEY` (full access — use only for
writing/creating) and `QDRANT_READONLY_API_KEY` (read only — prefer this for most connections).

**Open the dashboard (optional).** Go to $CLOUDRON-APP-ORIGIN/dashboard, sign in with your Cloudron
account, and paste the admin key into the API-key field.

**Connect another Cloudron app** (n8n, OpenWebUI, AnythingLLM): in that app's own settings, set its
Qdrant URL to $CLOUDRON-APP-ORIGIN and paste a key. See `docs/INTEGRATIONS.md` for per-app recipes.

**Connect your own code:** REST at $CLOUDRON-APP-ORIGIN, or gRPC at the host and port under this
app's Location settings (for Rust `rig-qdrant`; plain TCP, see the README security section).

**Test from your own computer:** `curl $CLOUDRON-APP-ORIGIN/collections -H "api-key: PASTE-READONLY-KEY-HERE"`.
Use the read-only key for anything that only reads; use the admin key only for apps that create
collections or write points.

**Good to know.** JWT and RBAC are on — mint scoped tokens in the dashboard's Access Tokens panel
(rotating the admin key revokes them all). The memory limit is 2 GB; Qdrant rejects writes near the
limit rather than being killed. Full topology, security, and integration recipes are in the README
and `docs/INTEGRATIONS.md`.
