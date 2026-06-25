# Changelog

[1.0.0]
- Initial release. Packages Qdrant v1.18.2 on cloudron/base:5.0.0.
- Two-surface topology on a single domain: the dashboard (/dashboard) behind the Cloudron
  proxyAuth addon, the REST and gRPC data plane in front of it and protected by Qdrant's API
  key.
- Generates a strong admin key and a separate read-only key on first start. Enables JWT and
  role-based access control for scoped tokens.
- Security hardening: telemetry disabled, snapshot recovery from remote URLs refused.
- Memory protection: strict-mode resident-memory guard (reject writes, stay alive) together with
  on-disk payload, so the service degrades rather than being killed when memory runs low.
- gRPC exposed on a Cloudron TCP port for high-throughput clients such as rig-qdrant.
- All state under /app/data, covered by Cloudron backup. An optional in-container snapshot cron
  (off by default) writes an extra consistent artifact into the backup.
