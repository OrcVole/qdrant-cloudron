# Packaging notes (running log)

Hard-won, verified learnings from packaging Qdrant for Cloudron. Updated every phase. This is the
source for the forum write-up. Each entry says what was verified empirically versus assumed.

## Pinned facts

- Upstream image: `qdrant/qdrant:v1.18.2@sha256:75eab8c4ba42096724fdcfde8b4de0b5713d529dde32f285a1f86fdcb2c9e50c` (multi-arch OCI index, amd64 + arm64).
- Base image: `cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c` (Ubuntu 24.04, glibc 2.39). This digest matches the one published in the Cloudron packaging skill. No newer base tag exists as of 2026-06-25.
- Single source of the upstream version: the `QDRANT_VERSION` build argument in `Dockerfile`. The manifest mirrors it in `upstreamVersion`.

## Phase 0 and 1 (recon and the container)

### Verified empirically (podman build and run on amd64)

- The qdrant binary is dynamically linked against `libc`, `libm`, `libgcc_s`, `libunwind`, and `liblzma`, all of which `cloudron/base:5.0.0` provides. `ldd` resolves cleanly and `qdrant --version` prints `qdrant 1.18.2`. The linkage gate runs inside the Dockerfile so a future glibc-floor bump fails the build, not runtime.
- The dashboard SPA is served at `/dashboard` and every static asset loads under `/dashboard/` (the built `index.html` references `/dashboard/favicon.ico` and `/dashboard/assets/...`). This is what makes a `proxyAuth` wall scoped to `path: /dashboard` cover the entire UI.
- `/healthz`, `/livez`, and `/readyz` all return 200 and bypass the API key. `/readyz` returns 503 until shards are ready, which on Cloudron risks a restart loop during collection load, so the health check uses `/healthz` (200 as soon as the listener binds).
- The API is closed by the key: `/collections` with no key returns Qdrant's own `401` with the body `Must provide an API key or an Authorization bearer token` (plain text, not a redirect). The admin key works as both the `api-key` header and `Authorization: Bearer`. The read-only key returns 200 on reads and 403 on writes. `/metrics` is also key-protected (not in the open whitelist).
- The memory guard is real and takes effect: a new collection created on a fresh install reports `strict_mode_config: { enabled: true, max_resident_memory_percent: 85, max_disk_usage_percent: 90 }`, seeded from the operator config. This is the degrade-not-crash mechanism (reject writes, stay alive). It counts the jemalloc heap, not the memory-mapped page cache, so it is paired with `on_disk_payload`.
- Telemetry is off: the boot log prints `Telemetry reporting disabled`. Distributed mode is off (`Distributed mode disabled`), so the p2p port 6335 is never bound.
- Persistence and idempotent boot: a collection and its points survive a container restart, and the second boot logs `existing API keys found` / `existing operator config found` (no reseed, no clobber).

### Corrections to the original brief (verified against v1.18.2 source and config)

- Memory: Qdrant v1.18 does have a cgroup-aware resident-memory guard (`strict_mode.max_resident_memory_percent`, a percent of the container limit). The brief assumed there was none and that a byte ceiling had to be templated from `CLOUDRON_MEMORY_LIMIT`. The percent form is simpler and needs no templating.
- Snapshot URL recovery defaults to enabled (an SSRF risk), so the package disables it with `service.enable_snapshot_url_recovery: false`.
- The deprecated `search`/`recommend`/`discover` endpoints are still present in 1.18.2 (deprecated, not removed). The real upgrade hazard is the storage format: RocksDB was fully removed in 1.18.0 and the Gridstore migration is one-way (no downgrade).
- io_uring (`storage.performance.async_scorer`) is opt-in and left off; there is no confirmed graceful fallback if the syscalls are blocked by seccomp.

### Cloudron-specific gotchas confirmed

- The `proxyAuth` addon key is camelCase. The packaging skill's addon reference lists it lowercase, which fails manifest validation. (Confirmed by the reference package's own debugging notes and the live docs.)
- Qdrant writes a `.qdrant-initialized` marker into its working directory, which is the read-only `/app/code`. The package runs Qdrant from a writable working directory under `/run/qdrant` with the dashboard and config symlinked in, so every Qdrant write stays inside an allowed path. Setting `RUN_MODE=production` makes Qdrant read the operator config (`config/production.yaml`, linked to the persisted file) as its overlay and also silences the default `config/development not found` notice.
- No YAML-rewriting tool (such as yq) is needed: unlike some apps, the Qdrant dashboard manages the database through the API and does not rewrite the server config file, so the package keeps a minimal runtime (single binary, no added tools).
- Config layering used: upstream `config/config.yaml` (baked defaults) then `config/production.yaml` (operator-editable, seeded from a template in `/app/data`) then `QDRANT__...` environment variables (package-forced: storage paths under `/app/data`, the API keys, host, and ports). Environment wins, so the forced infrastructure values cannot be broken by an operator edit.

### Build and host notes

- The Docker daemon was down on the build host; rootless `podman` builds the image fine. Use `127.0.0.1` rather than `localhost` for local smoke tests (rootless port maps are IPv4).
- The built image is roughly 2.7 GB, which is expected: `cloudron/base` is a full Ubuntu with Node and tooling.

## Phase 2 (SSO topology) — verified on the live box

Installed as a test app with an on-server build (`cloudron install --location <app> -p QDRANT_GRPC_PORT=6334`) and ran `test/sso-topology.sh`. Every assertion passed against the real Cloudron proxy:

- `GET /dashboard` with no session returns `302` to `/login?redirect=/dashboard`. The dashboard is behind Cloudron single sign-on.
- `GET /collections` with no key returns Qdrant's own `401` (`Must provide an API key or an Authorization bearer token`), not a redirect. The data plane is not behind single sign-on.
- `GET /collections` with the admin key as `Authorization: Bearer` or as the `api-key` header returns `200`.
- `GET /healthz` with no auth returns `200`.
- gRPC on the TCP port behaves the same way: `qdrant.Qdrant/HealthCheck` with the key returns the version reply; without the key it returns `Unauthenticated: Must provide an API key...`. gRPC reflection is enabled (grpcurl lists `qdrant.Collections`, `qdrant.Points`, `qdrant.Qdrant`, `qdrant.Snapshots`, `qdrant.StorageRead`, `grpc.health.v1.Health`), so clients need no .proto file.

This confirms the path-scoped `proxyAuth` design: the wall covers only `/dashboard`, and the REST and gRPC data planes are left to Qdrant's API key. The gRPC TCP port was reachable on the app's public domain at the chosen host port, so this box's domain is not Cloudflare-proxied; on a Cloudflare-proxied domain the raw TCP port would need a DNS-only record.

The icon is the official Qdrant mark (the gradient cube symbol), rendered to a 256x256 PNG from the upstream SVG on a white background. It is used to identify the packaged software (nominative use); the package is not affiliated with or endorsed by the Qdrant project, as stated in DESCRIPTION.md.

## Phase 3 (upgrade survival) — verified on the live box

Seeded three known points, edited the operator config (`max_resident_memory_percent` 85 to 70) through `cloudron exec`, then ran `cloudron update`. After the update: the points survived, the operator edit was not reseeded (start.sh found the existing config), a collection created after the update inherited the value 70, the admin key was unchanged, the app was healthy, and the boot logs were clean (`existing API keys found`, `existing operator config found`, `cgroup memory.max=2147483648`, no WARN or permission lines). The same `cloudron update` re-read `logo.png`, so the icon refreshed without an image change, and the on-server build ran the linkage gate as a build step.

A `cloudron update` takes a pre-update backup automatically, so a rollback is restoring that backup, not running an older binary. Qdrant's storage format moves forward only (RocksDB removed in 1.18.0, Gridstore migration one-way), so multi-minor jumps are taken one minor at a time (documented in UPGRADING.md; not exercised here because both versions share the format).

## Phase 4 (backup correctness) — verified on the live box, the gap closed

This is the slice the previous package reasoned about but did not test. Ran the full cycle on the throwaway:

1. Confirmed 100 percent of state is under `/app/data`: storage and snapshots paths are forced there by environment variables, and the operator config and keys live there too.
2. `cloudron backup create` (an app-level backup; the box picked one of its backup sites) captured the storage, including the segments and the write-ahead log.
3. `cloudron clone --backup <id> --location qdrant-bak...` restored the backup into a brand new, clean app, never over an existing one. Two practicalities: clone needs a pseudo-TTY because it prompts for a new gRPC host port (the source's is taken), and `--backup latest` did not resolve on a multi-backup-site box, so a concrete backup id from `cloudron backup list` was used.
4. On the restored clean app, every asserted item survived: the three points and their payloads, the operator config edit (70), and the admin API key (byte-identical to the source, so the same key authenticates), and the app was healthy. A collection created on the restored app inherited the restored config value.

Consistency model: Cloudron backs up `/app/data` as a live copy while the app runs. That is crash-consistent, not transactionally consistent, but Qdrant's write-ahead log replays on restore, and the empirical cycle above confirms a clean restore. For a transactionally consistent artifact regardless, the opt-in snapshot cron (off by default) writes a full Qdrant snapshot into the backup.

## Phase 5 (integrations) — core path verified live

REST plus key and gRPC plus key are both verified live (the SSO topology run). The read-only key returns 403 on writes and 200 on reads. A full retrieval round-trip was exercised end to end against the test app: fastembed (BAAI/bge-small-en, 384 dimensions) embedded three documents, the package stored them over REST with the key, and a semantic query returned the correct document (score 0.74). Ollama on the test box required its own API key, so its recipe is config-verified only. The sibling app user interfaces (agentgateway, n8n, OpenWebUI) were not driven, to respect the do-not-disturb rule; their recipes are verified at the Qdrant boundary (the REST or gRPC plus key path they use) and shipped as example configs under `config/examples/`.

A client-side note: the Python qdrant-client timed out connecting to the app domain from the build host (an IPv6 or happy-eyeballs quirk on that host; curl and grpcurl to the same domain worked throughout), so the round-trip stored and searched through curl. This is a client-host networking detail, not a package issue.
