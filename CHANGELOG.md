# Changelog

[1.0.4]

- Upstream Qdrant v1.19.0 to 1.19.1. Patch update with performance improvements and bug fixes. No data format changes, migrations, or schema updates required.
- New optional config settings (all commented out by default): wal_retain_closed and three HTTP timeout options (http_keep_alive_timeout_sec, http_client_request_timeout_sec, http_client_disconnect_timeout_sec).

[1.0.3]

- Upstream Qdrant v1.18.3 to v1.19.0. Includes a security fix for path traversal in S3-based
  snapshots (PR #10085), which is not reachable in this package because no S3 snapshot backend is
  configured.
- Four upstream deprecations, two of which this package's config template still sets and which
  continue to work: storage.on_disk_payload (superseded by payload.memory) and the per-collection
  strict_mode.max_resident_memory_percent (superseded by a cluster-wide quota API). Recorded rather
  than changed, so the version bump carries one variable and not three.
- Gate 3 ran the full leg on a throwaway installed from the published feed: update over live data
  then backup and restore from a named backup, with point count, search ordering and a canonical
  payload checksum identical at every stage. Qdrant is Restore-only, so the restore half is
  mandatory rather than discretionary.

[1.0.2]

- Bump upstream to Qdrant v1.18.3 (patch; two upstream commits, no auth or storage-format
  changes). Add the `<upstream>` tag to DESCRIPTION.md so update notifications name the
  upstream version, not just the package version.

[1.0.1]

- Set minBoxVersion to 9.1.0. The community versions-url install channel requires the iconUrl
  manifest field, and iconUrl requires Cloudron 9.1.0, so there is no 8.3.0-compatible
  versions-url manifest. Boxes below 9.1.0 can still install by building on the server (README).
- Flatten the post-install Admin notes (Cloudron renders the notes pane as inline markdown, with
  no blockquote cards or callouts) and default the examples to the read-only key.

[1.0.0]

- Initial release. Packages Qdrant v1.18.2 on cloudron/base:5.0.0.
- Two-surface topology on a single domain: the dashboard (/dashboard) behind the Cloudron
  proxyAuth addon, the REST and gRPC data plane in front of it and protected by Qdrant's API key.
- Generates a strong admin key and a separate read-only key on first start; JWT and RBAC enabled.
- Security hardening: telemetry disabled, snapshot recovery from remote URLs refused.
- Memory protection: strict-mode resident-memory guard plus on-disk payload.
- gRPC exposed on a Cloudron TCP port for high-throughput clients such as rig-qdrant.
- All state under /app/data, covered by Cloudron backup; optional in-container snapshot cron.
