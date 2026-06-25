# Contributing

This repository is a thin, reproducible packaging layer for Qdrant on Cloudron. Read AGENTS.md first;
it is the contract and it encodes the settled decisions.

## Development workflow

1. Build the image locally (the Docker daemon is optional; rootless podman works):

   ```
   podman build -t qdrant-cloudron:test -f Dockerfile .
   podman run -d --name q -v qdata:/app/data -p 127.0.0.1:6333:6333 qdrant-cloudron:test
   ```

   A local smoke test needs a volume mounted at `/app/data`, or the entrypoint fails at the first
   chown. Use `127.0.0.1`, not `localhost`, because rootless port maps are IPv4.

2. Install or update on a throwaway Cloudron app (on-server build, no local Docker needed):

   ```
   cloudron install --location qdrant-test.example.com -p QDRANT_GRPC_PORT=6334
   cloudron update  --app qdrant-test.example.com
   ```

3. Run the gates that your change touches:
   - `test/sso-topology.sh` after any topology or manifest change.
   - `test/upgrade.sh` on a version bump.
   - `test/backup-restore.sh` after any change to the data layout.
   - `test/io_uring-check.sh` inside the container if you touch the performance config.

4. Update the docs your change touches (AGENTS.md section 8 lists what), including
   docs/PACKAGING-NOTES.md with what you verified versus assumed.

## House style

Markdown and open formats only. No em dashes. Full words rather than contractions. Scripts begin with
`set -euo pipefail` and print `==>` markers. Pin versions; never use a floating tag.

## Releasing

See docs/RELEASING.md for the full procedure and the gate list. The upstream version lives only in the
`QDRANT_VERSION` build argument; the manifest mirrors it.

## Path to official Cloudron inclusion

The community-app channel (`CloudronVersions.json`, installed with `cloudron install --versions-url`)
makes this installable by others before any official review. Reviewers look for a clean multi-stage
Dockerfile on the current base, correct read-only filesystem handling, a working health check, instant
usability, sensible default security, a complete manifest with an icon, and clear documentation. Keep
the package thin and the upstream unpatched.
