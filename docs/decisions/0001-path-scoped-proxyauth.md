# 0001: Protect the dashboard with a path-scoped proxyAuth, leave the data plane to the API key

Status: accepted (verified on a live Cloudron box, 2026-06-25)

## Context

Qdrant exposes two surfaces on a single HTTP port (6333): the human dashboard (a single-page app
under /dashboard) and the programmatic REST API (/collections, /points, /snapshots, and so on).
gRPC is on a second port (6334). Qdrant has no UI authentication of its own, and its API is open
by default. On Cloudron an app's endpoints are reachable directly unless the app opts into the
proxyAuth addon, which authenticates visitors against Cloudron single sign-on.

The reference package this one is modelled on put its two surfaces on two separate subdomains (an
httpPorts entry for the data plane) with proxyAuth covering the whole primary domain. Qdrant
cannot use that shape, because it serves the dashboard and the API on the same port, split only by
path. A whole-domain proxyAuth wall would redirect API clients to a login page, which a non-browser
client cannot satisfy, breaking every integration.

## Decision

Scope the proxyAuth addon to the dashboard path only:

    "addons": { "proxyAuth": { "path": "/dashboard", "supportsBearerAuth": true } }

This places Cloudron single sign-on in front of /dashboard (and its assets, which all load under
/dashboard/), and leaves every other path open at the network level: the REST API, /metrics, the
health endpoints, and the root. Those are protected by Qdrant's own API key, generated on first
run. gRPC on the TCP port is likewise protected by the API key.

Set supportsBearerAuth: true so a request carrying an Authorization: Bearer token is forwarded
through rather than redirected, giving uniform "a valid key is never redirected" behaviour across
all paths. This is acceptable here, unlike on a whole-domain admin wall, because the API key
already grants full access, so forwarding a key-bearing request to the dashboard document grants
nothing the key does not already grant. The reference package omits supportsBearerAuth because its
wall covers an entire admin domain with no other authentication; here the wall covers only the
static UI and the data plane is open and key-protected regardless.

Declare proxyAuth from first install, because Cloudron cannot add it to an existing app later.

## Consequences

- An unauthenticated API request returns Qdrant's own 401 (a plain body), not a 302 to a login
  page, so programmatic clients and sibling Cloudron apps work.
- The dashboard is reachable only by a logged-in Cloudron user. After signing in, the user pastes
  the admin key into the dashboard to operate the database.
- Verified on a live box: GET /dashboard with no session returns 302 to the Cloudron login; GET
  /collections with no key returns Qdrant's 401; with the key it returns 200; gRPC with the key
  returns the health reply and without the key returns Unauthenticated.
- If a future Qdrant release served a dashboard asset from the site root, the wall would not cover
  that asset (still harmless, the asset is static). The asset paths are re-checked on every
  upstream bump (docs/UPGRADING.md).
