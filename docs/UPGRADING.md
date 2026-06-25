# Upgrading

How to move this package to a new upstream Qdrant version, safely and repeatably.

Unlike a stateless app, Qdrant is a database with an on-disk format, so an upgrade carries real
data risk. Read this before changing the pin.

## Version policy

- The upstream version is pinned in exactly one canonical place: the `QDRANT_VERSION` build
  argument in `Dockerfile`. The manifest mirrors it in `upstreamVersion`, but the Dockerfile
  argument is authoritative. Both the upstream image and the base image are also pinned by digest.
- Never use a floating tag such as `latest`. A reproducible build is the point.
- Track stable releases only.
- The package `version` in the manifest is our own semver and moves independently of the upstream
  version. Bump it on every published change.

## Minimum box version

The package declares `minBoxVersion 9.1.0`. This is the floor of the community versions-url install
channel, not of the software. The channel requires the `iconUrl` manifest field, and `iconUrl`
requires box 9.1.0 (a versions-url manifest without `iconUrl` fails validation), so there is no
8.3.0-compatible versions-url manifest. The Qdrant binary and `cloudron/base:5.0.0` run on Cloudron
8.3 and up; to install on a box below 9.1.0, build from source on the server (`cloudron install` from
a clone of this repository), which uses the `file://logo.png` icon and does not require `iconUrl`.

## Current pin

- Upstream: `v1.18.2`, `qdrant/qdrant:v1.18.2@sha256:75eab8c4ba42096724fdcfde8b4de0b5713d529dde32f285a1f86fdcb2c9e50c`.
- Base: `cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c`.

## Storage format and the one-way migration (read first)

Qdrant has changed its on-disk storage engine over time, and the migration is **forward only**:

- Gridstore became the default for payload and sparse storage in v1.13.
- Mutable Gridstore and the active migration landed in v1.16.0 and v1.16.1.
- RocksDB was fully removed in v1.18.0. A node started on v1.18 migrates any remaining
  RocksDB-format data to Gridstore on first boot, and that migration is one-way: a downgrade to an
  older Qdrant is not supported once data has been migrated.

Consequences for upgrades:

- **Upgrade one minor version at a time.** Do not jump several minors at once. Each minor may carry
  a migration step that assumes the previous minor's format.
- **A downgrade is not a rollback.** If an upgrade goes wrong, restore from the pre-update backup
  (Cloudron takes one automatically before `cloudron update`), do not try to run an older binary on
  upgraded data.
- Crossing the 1.16 to 1.18 window migrates RocksDB data to Gridstore. Budget time and disk for it
  on a large instance, and confirm health after the first boot on the new version.

## Release gates (run on every version bump, no exceptions)

### Gate 1: binary and base linkage (build-time)

The qdrant binary is dynamically linked against glibc. A future upstream build on a newer toolchain
could require a glibc newer than the base provides, and that fails at runtime, not at build time.
The Dockerfile runs the linkage check as a build step, so a bad pin fails the build:

```
ldd /app/code/qdrant     # every line must resolve, no "not found"
/app/code/qdrant --version
```

If either fails, raise the `cloudron/base` pin to a digest that provides the required glibc, re-run,
and only then continue. At the current pin the binary needs at most glibc 2.39 and links libc, libm,
libgcc_s, libunwind, and liblzma, all present on base 5.0.0.

### Gate 2: update survival (real `cloudron update`)

A user's data and their edits to `/app/data/config/production.yaml` must survive an update. Verified
on a real box at this pin: with three known points and an operator edit
(`max_resident_memory_percent` changed to 70) in place, `cloudron update` preserved the points, left
the operator config unchanged (start.sh seeds it only when absent), and a collection created after
the update inherited the edited value. Re-run `test/upgrade.sh` (or the equivalent) on every bump and
confirm data and config survive and the app is healthy.

### Gate 3: migration on a throwaway (for a real minor jump)

When the new pin crosses a minor boundary, exercise the migration on a throwaway before shipping:
install the current package, seed known data, then update to the new version and confirm the data is
intact and the app healthy. A same-version rebuild does not exercise the storage migration, so it
stays unproven until a real version change is tested.

## Standard bump steps

1. Confirm the new stable tag exists on the upstream releases page
   (https://github.com/qdrant/qdrant/releases) and the image is published. Resolve its digest with
   `skopeo inspect --format '{{.Digest}}' docker://qdrant/qdrant:<tag>`.
2. Change the version in the canonical places:
   - `Dockerfile`: `ARG QDRANT_VERSION=v<new>` and the pinned `@sha256:` digest on the upstream
     `FROM` line (both must move together).
   - `CloudronManifest.json`: `upstreamVersion` to `<new>`, and bump the package `version`.
3. Run Gate 1 (build and linkage), then Gate 2 and, for a minor jump, Gate 3.
4. Add a `[x.y.z]` entry to `CHANGELOG.md` and update docs/PACKAGING-NOTES.md.
5. Follow docs/RELEASING.md to build, push, pin the digest, and publish.

## What to watch for in upstream changes

- **Config keys:** the package sets `QDRANT__SERVICE__API_KEY`, `QDRANT__SERVICE__READ_ONLY_API_KEY`,
  `QDRANT__SERVICE__HTTP_PORT`, `QDRANT__SERVICE__GRPC_PORT`, `QDRANT__STORAGE__STORAGE_PATH`, and
  `QDRANT__STORAGE__SNAPSHOTS_PATH` through the environment, and ships `jwt_rbac`,
  `enable_snapshot_url_recovery`, `telemetry_disabled`, `on_disk_payload`, and
  `storage.collection.strict_mode.max_resident_memory_percent` in the operator config. Re-verify
  these names against the new version's `config/config.yaml` and source.
- **Dashboard asset paths:** the proxyAuth wall depends on every dashboard asset loading under
  `/dashboard/`. Re-check on a major UI change (see docs/decisions/0001).
- **Health endpoints:** `/healthz`, `/livez`, `/readyz`. The health check uses `/healthz`.
- **Image layout:** the multi-stage copy depends on `/qdrant/qdrant`, `/qdrant/static`, and
  `/qdrant/config/config.yaml` in the upstream image. Re-verify on a major image change.
