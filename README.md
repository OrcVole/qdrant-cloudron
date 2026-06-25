# Qdrant for Cloudron

This repository packages [Qdrant](https://github.com/qdrant/qdrant), the open-source vector
database written in Rust, as a Cloudron application. It keeps the upstream binary unmodified and
adds only a Cloudron-conformant runtime: a multi-stage Dockerfile, an entrypoint that prepares and
secures the runtime, a manifest, and a hardened default configuration.

Qdrant and the Qdrant name and logo are trademarks of their respective owner. This package is
community-maintained and is not affiliated with or endorsed by the Qdrant project.

## Topology

Qdrant serves a human dashboard and a programmatic API on the same HTTP port, split by path, plus
gRPC on a second port. The two surfaces need different protection, so this package treats them
differently on a single domain:

| Surface | Path or port | Behind Cloudron login | Authentication |
|---|---|---|---|
| Dashboard (web UI) | `/dashboard` on the app domain | Yes (the `proxyAuth` addon, scoped to `/dashboard`) | Cloudron single sign-on |
| REST API | every other path on the app domain | No | Qdrant API key |
| gRPC API | a Cloudron TCP port | No | Qdrant API key |

The dashboard has no authentication of its own, so it sits behind Cloudron login. The REST and gRPC
data planes carry programmatic traffic that cannot complete an interactive sign-in, so they stay in
front of Cloudron login and are protected by Qdrant's own API key. An unauthenticated API request
therefore returns Qdrant's own `401`, not a redirect to a login page, which is what lets sibling
apps and external clients authenticate with the key. See `docs/decisions/0001-path-scoped-proxyauth.md`.

## Client URLs

After install, with `<domain>` the app domain you chose:

- Dashboard: `https://<domain>/dashboard` (sign in with Cloudron, then paste the admin key)
- REST API: `https://<domain>` (for example `GET /collections`)
- gRPC API: `<host>:<port>` as shown for this app's "Qdrant gRPC API" port

REST, with the key as a header or a bearer token:

```
curl https://<domain>/collections -H "api-key: <admin-key>"
curl https://<domain>/collections -H "Authorization: Bearer <admin-key>"
```

A request with no key, or the wrong key, returns `401`.

## The API key

Qdrant is insecure by default: its API is open. This package closes that. On first start it
generates a strong admin key and a separate read-only key, stored at
`/app/data/.secrets/keys.env`. To read them, open a Terminal for the app (or `cloudron exec`) and:

```
cat /app/data/.secrets/keys.env
```

- The admin key grants full read and write access.
- The read-only key grants read access only (writes return `403`).
- Either can be sent as the `api-key` header or as an `Authorization: Bearer` token.

JWT and role-based access control are enabled, so from the dashboard "Access Tokens" panel you can
mint scoped, read-only or per-collection tokens, signed by the admin key, to hand to integrators.
Rotating the admin key revokes every issued token.

## What ships by default

The default configuration is hardened for a shared, memory-limited host:

- Telemetry is disabled.
- Snapshot recovery from arbitrary remote URLs is refused (server-side request forgery hardening).
- Strict mode rejects writes (while staying alive and serving reads) when resident memory
  approaches the container limit, instead of being killed into a restart loop.
- Point payloads are kept on disk to save RAM.

All persistent state lives under `/app/data`, which Cloudron backs up.

## Memory and large collections

The default memory limit is 2 GB. Qdrant is configured to degrade rather than crash: when resident
heap memory approaches the limit it rejects writes and keeps serving reads. This guard counts the
heap, not the memory-mapped page cache, so for larger collections move data off the heap as well:

- Raise the memory limit in the app's Resources settings.
- Store vectors on disk (`vectors.on_disk: true`, per collection or as a default in
  `/app/data/config/production.yaml`).
- Use TurboQuant quantization (new in Qdrant 1.18), which compresses vectors about 8x at `bits4`
  while keeping recall close to scalar quantization, so more fits in RAM:

```json
{ "quantization_config": { "turbo": { "bits": "bits4", "always_ram": true } } }
```

See `docs/INTEGRATIONS.md` for worked examples.

## Configuration

Operator-tunable settings live in `/app/data/config/production.yaml`, seeded on first run and
yours to edit (restart the app after editing). The package forces a few infrastructure values
(the storage paths under `/app/data`, the API keys, the host, and the ports) through environment
variables, which override the file, so those cannot be changed by an edit. Everything else in the
file, including the security and memory defaults, is yours.

## Backup and restore

All state (storage, snapshots, the operator config, and the keys) is under `/app/data`, so
Cloudron's backup covers it. Cloudron backs up the directory as a live copy while the app runs.
Qdrant uses a write-ahead log, so a live copy is crash-consistent and replays the log on restore.
For a transactionally consistent artifact regardless, an optional in-container snapshot cron (off
by default) can write a full Qdrant snapshot into the backup; enable it by setting
`QDRANT_SNAPSHOT_CRON=enabled` in the app's environment. See `docs/UPGRADING.md` for the
consistency model and `docs/DEBUGGING.md` for restore-from-snapshot.

## Updating

The upstream version is pinned in one canonical place, the `QDRANT_VERSION` build argument in the
`Dockerfile`. `cloudron update` rebuilds and updates the app, taking a backup first. Qdrant moves
its on-disk format forward only (a downgrade is not supported), and large jumps should be taken one
minor version at a time. See `docs/UPGRADING.md` for the version policy and the release gates.

## Security model

- The dashboard is protected by the Cloudron `proxyAuth` addon. It cannot be added after install,
  so it is declared from the start.
- The REST and gRPC data planes are protected by the Qdrant API key, generated on first run.
- gRPC runs over a Cloudron TCP port. That port is plain TCP and is not TLS-terminated by Cloudron,
  so treat the gRPC channel as you would any plaintext link on your network. REST runs over the
  Cloudron domain with Let's Encrypt TLS. A Cloudflare-proxied domain cannot forward the raw gRPC
  port; use a DNS-only record for it.

## Integrations

Qdrant is the vector store for a pure-Rust, Python-free retrieval stack (a Rust embedding service,
`rig`, and `agentgateway`), and it works with n8n, OpenWebUI, AnythingLLM, and others. See
`docs/INTEGRATIONS.md` for tested recipes and `docs/FOLLOWON-TEI.md` for the planned embedding
companion.

## Install

This package is published as a public image and a Cloudron community versions file. To install,
point the Cloudron CLI at the versions URL and choose a domain:

```
cloudron install \
  --versions-url https://raw.githubusercontent.com/OrcVole/qdrant-cloudron/main/CloudronVersions.json \
  --location qdrant.example.com
```

The image is pinned by digest in `CloudronVersions.json`, so every install pulls the exact build
that was published.

This community versions-url channel requires **Cloudron 9.1.0 or newer**: the channel mandates the
`iconUrl` manifest field, and `iconUrl` requires box 9.1.0, so a versions-url manifest cannot target
a lower floor (omitting `iconUrl` makes versions-url validation fail). On a box below 9.1.0, install
by building from source instead (next section), which works on Cloudron 8.3 and up and takes its icon
from the `file://logo.png`.

## Build from source

To build the image yourself instead of pulling the published one, clone this repository and run
the Cloudron build flow (it builds on the server, so no local Docker is needed), then install:

```
cloudron install --location qdrant.example.com
```

See `AGENTS.md` for the packaging contract, `docs/DEBUGGING.md` for the runbook, and
`docs/RELEASING.md` for the release procedure.
