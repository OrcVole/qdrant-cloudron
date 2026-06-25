# AGENTS.md

This file is the working contract for any AI agent or human who edits this repository. Read it
fully before changing anything. It encodes decisions that are already settled, so that you do not
relitigate them and do not regress conformance.

If you are an AI agent: treat the rules in "Golden rules" as hard constraints. When a request
conflicts with them, stop and surface the conflict rather than working around it.

This repository packages **Qdrant** (https://github.com/qdrant/qdrant, Apache-2.0, a vector
database written in Rust) as a **Cloudron-conformant application**. The goals, in order: (1) it
runs cleanly and securely on Cloudron, (2) the repository is public so others can use it, and (3)
it is written to a standard where the Cloudron team could adopt it as an official application.

---

## 1. Golden rules (non-negotiable)

1. **Conformance first.** The Cloudron packaging rules in section 5 override convenience. A change
   that writes outside the allowed paths, runs as root, or skips the health check is wrong.
2. **Pin versions. Never use floating tags.** The upstream version lives in exactly one canonical
   place (the `QDRANT_VERSION` build argument). Both base images are pinned by digest. See section 4.
3. **Do not break the topology.** The dashboard and the data plane are two surfaces with two
   security models. See section 6. Never place the Cloudron proxyAuth wall in front of the REST or
   gRPC data plane.
4. **Persisted state lives only in `/app/data`.** Storage, snapshots, the operator config, and the
   keys all live there, which is what makes the Cloudron backup complete.
5. **Fail loud, log clearly.** Every script fails fast and prints greppable `==>` markers. An agent
   debugging this later should be able to find the failure from logs alone.
6. **Every change updates its documentation.** Code and docs ship together.
7. **House style for prose:** Markdown and open formats only. No em dashes. Full words rather than
   contractions.
8. **Verify, do not assume.** When an upstream option, image layout, config key, or Cloudron
   capability might have changed, check the live docs and confirm empirically. Record what you
   verified versus assumed (see docs/PACKAGING-NOTES.md).

---

## 2. What this repository is and is not

- It **is** a thin, reproducible packaging layer: a Dockerfile, an entrypoint, a manifest, a
  hardened default configuration, and documentation.
- It **is not** a fork of Qdrant. The binary is not patched. The package consumes the official
  release image and adapts only the runtime environment to Cloudron.
- Upstream owns the database behaviour. This package owns the packaging, the security defaults, the
  topology, and the upgrade path.

---

## 3. Repository layout

```
.
├── AGENTS.md                  # this file: the contract
├── CONTRIBUTING.md            # dev workflow and the path to official inclusion
├── README.md                  # user-facing: topology, install, security
├── DESCRIPTION.md             # app store description
├── CHANGELOG.md               # package changelog (bracket [x.y.z] form)
├── POSTINSTALL.md             # shown after install
├── Dockerfile                 # multi-stage; canonical QDRANT_VERSION lives here
├── start.sh                   # entrypoint: prepare /app/data, generate keys, exec qdrant
├── snapshot.sh                # opt-in scheduler task: full snapshot into /app/data
├── CloudronManifest.json      # metadata, ports, addons, healthCheckPath
├── CloudronVersions.json      # community publishing channel
├── logo.png                   # 256x256 icon (the official Qdrant mark)
├── .dockerignore              # keeps secrets and repo cruft out of the build context
├── .gitignore                 # keeps secrets out of git
├── config/
│   └── production.yaml.template  # hardened operator config, seeded to /app/data on first run
├── docs/
│   ├── UPGRADING.md           # version policy and release gates
│   ├── DEBUGGING.md           # the runbook
│   ├── RELEASING.md           # the release procedure
│   ├── INTEGRATIONS.md        # connecting Qdrant to sibling apps
│   ├── PACKAGING-NOTES.md     # running log of verified learnings
│   ├── FOLLOWON-TEI.md        # stub for the embedding companion package
│   └── decisions/             # one short ADR per non-obvious decision
└── test/
    ├── sso-topology.sh        # the two-surface assertions
    ├── backup-restore.sh      # backup then restore into a clean app, verify
    ├── upgrade.sh             # cross-version update survival
    ├── io_uring-check.sh      # io_uring under container seccomp
    └── lib.sh                 # shared seed and verify helpers
```

---

## 4. Pinned versions and the single source of truth

**Canonical upstream version:** the `QDRANT_VERSION` build argument in `Dockerfile`. Nothing else
hardcodes the upstream version. The manifest mirrors it in `upstreamVersion`. The package `version`
in the manifest is our own semver and moves independently.

| Component | Pin |
|---|---|
| Qdrant (upstream) | `v1.18.2`, image `qdrant/qdrant:v1.18.2@sha256:75eab8c4ba42096724fdcfde8b4de0b5713d529dde32f285a1f86fdcb2c9e50c` |
| Cloudron base | `cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c` (Ubuntu 24.04, glibc 2.39) |

The qdrant binary requires glibc not newer than 2.39 at this pin and is dynamically linked against
`libc`, `libm`, `libgcc_s`, `libunwind`, and `liblzma`, all present on the base. The Dockerfile runs
a linkage gate at build time, so a future upstream toolchain bump that raised the glibc floor would
fail the build rather than fail silently at runtime. Re-run the gates in docs/RELEASING.md on every
bump.

---

## 5. Cloudron conformance rules

- **Base image:** the final build stage is `cloudron/base`, pinned by digest. A multi-stage build
  copies the qdrant binary, the dashboard static directory, and the upstream default config from
  the official image.
- **Read-only root filesystem.** Only `/tmp`, `/run`, and `/app/data` are writable. Qdrant is run
  from a writable working directory under `/run/qdrant` (with the read-only dashboard and config
  symlinked in) so that the marker file Qdrant writes to its working directory stays inside an
  allowed path.
- **Code under `/app/code`** (read-only at runtime). **State under `/app/data`** (the `localstorage`
  addon, the only backed-up location). Chown `/app/data` in `start.sh` before dropping privileges.
- **Run as the `cloudron` user** via `gosu cloudron:cloudron`.
- **Health check:** `healthCheckPath` is `/healthz`, which returns 200 as soon as the listener
  binds and bypasses the API key. Not `/readyz` (it returns 503 until shards load, which would risk
  a restart loop). See docs/decisions/0002-health-check-path.md.
- **Instant usability:** no setup screen. The app works right after install; the generated keys are
  surfaced through `postInstallMessage`.

---

## 6. Architecture and topology (the crux)

Qdrant exposes two surfaces on one HTTP port (6333), split by path, plus gRPC on 6334:

- **Dashboard**, the single-page app under `/dashboard`. It has no authentication of its own.
- **REST and gRPC data plane**, everything else. Protected by Qdrant's API key.

The package scopes the `proxyAuth` addon to `/dashboard` only, so Cloudron single sign-on guards the
UI while the data plane stays open at the network level and is protected by the key. This is why an
unauthenticated API request returns Qdrant's own 401, not a login redirect. See
docs/decisions/0001-path-scoped-proxyauth.md. **Never** widen proxyAuth to cover the data plane, and
never add a secondary auth in front of the REST or gRPC paths.

Qdrant is insecure by default. The package generates an admin key and a read-only key on first run,
enables JWT and role-based access control, disables telemetry, and refuses snapshot recovery from
remote URLs. Keys are injected from `/app/data/.secrets/keys.env` through `QDRANT__SERVICE__API_KEY`
and `QDRANT__SERVICE__READ_ONLY_API_KEY`, never written into the operator config file.

---

## 7. Configuration model

Three layers, lowest to highest precedence:

1. The upstream `config/config.yaml` (baked defaults), read because Qdrant runs with
   `RUN_MODE=production` from a working directory whose `config/config.yaml` links to it.
2. `/app/data/config/production.yaml` (the operator file), seeded on first run from
   `config/production.yaml.template` and linked as the `production` run-mode overlay. This holds the
   security and memory defaults and is the operator's to edit.
3. `QDRANT__...` environment variables exported by `start.sh` (package-forced: storage paths under
   `/app/data`, the API keys, the host, and the ports). Environment wins, so these cannot be broken
   by an operator edit.

First-run seeding is idempotent: keys and the operator config are written only when absent, so an
update or restart never clobbers them.

---

## 8. AI-debuggability requirements

- `start.sh` begins with `#!/bin/bash` and `set -euo pipefail`.
- Print phase markers to stdout, each prefixed with `==>`, so logs are greppable and distinguishable
  from Qdrant's own lines.
- Echo the resolved runtime facts at startup (version, ports, storage paths, key presence), never
  secrets.
- First-run seeding must be idempotent.
- All runtime state is files under `/app/data`. If you add state, document it in docs/DEBUGGING.md
  under "State on disk".
- Deterministic build: no floating tags, no unpinned installs.
- Comments explain why, not what, especially Cloudron-specific workarounds.

---

## 9. Build, install, test, update

```bash
# Build locally (the Docker daemon is optional; rootless podman works)
podman build -t qdrant-cloudron:test -f Dockerfile .

# Install or update on the target Cloudron (on-server build; no local Docker needed)
cloudron install --location qdrant.example.com -p QDRANT_GRPC_PORT=6334
cloudron update  --app qdrant.example.com

# Logs, exec, debug
cloudron logs -f --app qdrant.example.com
cloudron exec  --app qdrant.example.com
```

The test scripts in `test/` are the gates. Run `test/sso-topology.sh` after any topology change,
`test/backup-restore.sh` after any change to the data layout, and `test/upgrade.sh` on a version
bump. A change is not done until the relevant gate passes on a real box.

---

## 10. Path to official Cloudron inclusion

Reviewers look for: a clean multi-stage Dockerfile on the current base, correct read-only filesystem
handling, a working health check, instant usability with no setup screen, sensible default security,
a complete manifest with metadata and icon, and clear documentation. Keep the package thin and the
upstream unpatched. The community-app channel (`CloudronVersions.json`) is the route to make it
installable by others before any official review. See CONTRIBUTING.md.

---

## 11. Definition of done (pre-commit checklist)

- [ ] No write paths outside `/tmp`, `/run`, `/app/data` (verified on a real or local run).
- [ ] Runs as `cloudron`, not root.
- [ ] Upstream version pinned in exactly one canonical place; both base images pinned by digest.
- [ ] Topology unchanged, or the change is recorded in an ADR and README and re-verified with
      `test/sso-topology.sh`.
- [ ] `start.sh` uses `set -euo pipefail` and prints `==>` markers; first-run seeding is idempotent.
- [ ] Health check returns 2xx and is unauthenticated.
- [ ] README, CHANGELOG, PACKAGING-NOTES, and DEBUGGING updated as relevant.
- [ ] The relevant `test/` gate passes on the target Cloudron.
- [ ] No secret, personal host, email, or token in any tracked file (the anonymity sweep in
      docs/RELEASING.md).
- [ ] Prose follows house style: no em dashes, full words, open formats.
