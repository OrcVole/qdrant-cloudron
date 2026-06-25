# Changelog

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
