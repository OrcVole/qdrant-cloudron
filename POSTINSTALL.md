> **Qdrant is running and ready.** There is no setup wizard. Get your API key, then point your apps
> or your code at it whenever you want. Opening the dashboard is optional.
>
> ### 1. Get your API key
>
> Open a Terminal for this app (the `>_` button above) and run:
>
> ```
> cat /app/data/.secrets/keys.env
> ```
>
> It prints `QDRANT_ADMIN_API_KEY` (full access) and `QDRANT_READONLY_API_KEY` (read only). You give
> one of these keys to anything that connects to Qdrant.
>
> ### 2. Open the dashboard (optional)
>
> Open $CLOUDRON-APP-ORIGIN/dashboard, sign in with your Cloudron account, and paste the admin key
> into the API key field to browse and manage collections.
>
> ### Connecting apps and code (reference, not a step)
>
> You do not run anything here to finish setup. To use Qdrant from another Cloudron app (n8n,
> OpenWebUI, AnythingLLM), set its Qdrant URL to $CLOUDRON-APP-ORIGIN and paste a key in that app's
> own settings. From your own code, use REST at $CLOUDRON-APP-ORIGIN, or gRPC at the host and port
> shown under this app's Location settings (plain TCP, for clients like Rust `rig-qdrant`). To check
> the key works, run this from your own computer:
>
> ```
> curl $CLOUDRON-APP-ORIGIN/collections -H "api-key: PASTE-ADMIN-KEY"
> ```
>
> ### More
>
> JWT and RBAC are on: mint scoped, read-only or per-collection tokens in the dashboard's Access
> Tokens panel. The memory limit is 2 GB; Qdrant rejects writes near the limit instead of being
> killed. Full topology, security, and integration recipes are in the README and
> `docs/INTEGRATIONS.md`.
