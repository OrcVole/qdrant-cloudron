# Debugging

A runbook for diagnosing this package on Cloudron. It is written so that an agent with only the
repository and the logs can find and fix a failure. When you fix a new failure, add it to "Known
failures" with the symptom, the cause, and the fix.

## State on disk (where to look first)

Everything the package persists lives under `/app/data`:

- `/app/data/storage/` is the Qdrant storage engine (collections, segments, the write-ahead log,
  `raft_state.json`). Forced by `QDRANT__STORAGE__STORAGE_PATH`.
- `/app/data/snapshots/` holds Qdrant snapshots. Forced by `QDRANT__STORAGE__SNAPSHOTS_PATH`.
- `/app/data/config/production.yaml` is the operator-editable config, seeded on first run.
- `/app/data/.secrets/keys.env` holds the generated admin and read-only API keys (mode 0600).
- `/app/data/.initialized` is the package first-run marker.

`/run/qdrant` is the ephemeral working directory created on every boot (the dashboard `static` dir
and the `config` overlay are symlinked into it, and Qdrant writes its `.qdrant-initialized` marker
there). It is not persistent, by design. The rest of the filesystem is read-only except `/tmp`,
`/run`, and `/app/data`.

## Boot sequence

`start.sh` prints `==>` markers at each step. On every start it:

1. Prepares `/app/data` (creates storage, snapshots, config, secrets subdirectories) and fixes
   ownership to `cloudron`.
2. On first run only, generates the admin and read-only API keys into `/app/data/.secrets/keys.env`.
3. On first run only, seeds `/app/data/config/production.yaml` from the baked template. It never
   overwrites an existing key file or config.
4. Exports the package-forced settings (storage paths, keys, host, ports) as `QDRANT__...`
   environment variables, which override the config files.
5. Sets up the writable working directory `/run/qdrant`, sets `RUN_MODE=production`, and execs
   `qdrant` as the `cloudron` user.

To see the package startup sequence:

```
cloudron logs -f --app <app> | grep '==>'
```

A healthy start prints, in order: preparing `/app/data`, key generation or "existing API keys
found", config seeding or "existing operator config found", the resolved version and ports, the
working directory, and the exec line. If the sequence stops early, the last `==>` marker names the
phase that failed.

## Verifying a deploy (the smoke-test ladder)

A change is not done until this passes on the target Cloudron.

1. **Health.** The app shows healthy. `GET /healthz` returns 200.
2. **Two-surface topology.** Run `test/sso-topology.sh` with the app domain and the admin key. It
   asserts: `/dashboard` redirects to Cloudron login; `/collections` with no key returns Qdrant's
   401; `/collections` with the key returns 200; gRPC with the key works and without it is rejected.
3. **Write path.** Create a collection, upsert a point, read it back (see `test/lib.sh`).
4. **Persistence.** Restart the app and confirm the collection and points survive.
5. **Update survival.** `cloudron update` and confirm data and the operator config survive (Gate 2
   in docs/UPGRADING.md).
6. **Backup and restore.** `cloudron backup create`, then `cloudron clone --backup latest` into a
   fresh app, and confirm the data, the operator config, and the API key survive (see
   `test/backup-restore.sh`).

## Getting the API key

```
cloudron exec --app <app> -- cat /app/data/.secrets/keys.env
```

The admin key is `QDRANT_ADMIN_API_KEY`; the read-only key is `QDRANT_READONLY_API_KEY`.

## Known failures

Format: Symptom / Cause / Fix.

### Install fails: manifest validation rejects `/addons`
- **Symptom:** `cloudron install` rejects the manifest, pointing at `/addons`, before any build.
- **Cause:** the proxy-authentication addon key must be camelCase `proxyAuth`. The Cloudron
  packaging skill's addon reference lists it lowercase, which the box rejects.
- **Fix:** `"addons": { "proxyAuth": { "path": "/dashboard", "supportsBearerAuth": true } }`.

### Boot log: `Failed to create init file indicator: .qdrant-initialized: Permission denied`
- **Symptom:** a WARN at boot about not being able to write `.qdrant-initialized`.
- **Cause:** Qdrant writes a marker into its working directory, which would be the read-only
  `/app/code`.
- **Fix:** already handled. `start.sh` runs Qdrant from the writable `/run/qdrant` with `static` and
  `config` symlinked in. If this WARN returns, confirm the working-directory setup in `start.sh`.

### Boot log: `Config file not found: config/development`
- **Symptom:** a WARN about a missing `config/development` file.
- **Cause:** Qdrant's default run mode is `development`, so it looks for `config/development.yaml`.
- **Fix:** already handled. `start.sh` sets `RUN_MODE=production` and links the operator config as
  `config/production.yaml` in the working directory.

### App is OOM-killed or restarts under load
- **Symptom:** the app restarts when a collection grows, or the container is killed.
- **Cause:** the memory limit is too low for the working set. Qdrant keeps the HNSW graph and
  unquantized vectors in RAM unless told otherwise, and the strict-mode guard counts only the heap.
- **Fix:** raise the memory limit (Resources settings); set `vectors.on_disk: true` and
  `hnsw_index.on_disk: true` in `/app/data/config/production.yaml`; or use TurboQuant quantization.
  Confirm `storage.collection.strict_mode.max_resident_memory_percent` is set so writes are rejected
  rather than the process being killed. Strict mode applies to new collections; PATCH existing ones.

### `GET /metrics` returns 401
- **Symptom:** a Prometheus scrape of `/metrics` returns 401.
- **Cause:** `/metrics` is protected by the API key (it is not in Qdrant's open whitelist, which is
  only `/`, `/healthz`, `/livez`, `/readyz`).
- **Fix:** send the API key on the scrape, or a read-only key.

### gRPC client cannot connect on the data-plane port
- **Symptom:** a gRPC client times out or is refused on the TCP port.
- **Likely causes:** the domain is Cloudflare-proxied (the orange cloud proxies only HTTP, so the
  raw TCP port does not pass), or the wrong host or port is used.
- **Fix:** use a DNS-only (grey-cloud) record for the host that serves the gRPC port; use the host
  and port shown for the app's "Qdrant gRPC API" port; the channel is plaintext, so use `-plaintext`
  with grpcurl.

### io_uring and seccomp
- Qdrant can use io_uring for the async scorer (quantized multi-vector rescoring). The package
  leaves it off (`storage.performance.async_scorer` defaults to false), because Docker's default
  seccomp profile commonly restricts io_uring syscalls and there is no confirmed graceful fallback.
  Do not enable it expecting a speedup without testing on the target host. `test/io_uring-check.sh`
  reports the container seccomp posture.

## Iterating with a debug install

A debug install gives a writable root filesystem, which is the fastest way to find what the app
tried to write outside the allowed paths:

```
cloudron install --debug --location qdrant.example.com
cloudron exec --app qdrant.example.com
#   inside: find / -mmin -30 -not -path '/proc/*' -not -path '/sys/*'
```

Turn debug mode off when done: `cloudron configure --no-debug --app qdrant.example.com`.

## When you are stuck

- Re-read AGENTS.md sections 5 and 6. Most failures are a conformance or topology mistake.
- Reproduce locally with `podman run` and a mounted `/app/data` volume before blaming Cloudron.
- Record whatever you learn here so the next agent does not start from zero.
