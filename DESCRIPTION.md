Qdrant is a high-performance, open-source vector database and similarity-search engine written
in Rust. It stores high-dimensional vectors together with JSON payloads and serves fast
nearest-neighbour search over REST and gRPC, which makes it a building block for
retrieval-augmented generation, semantic search, recommendations, and other AI workloads.

This package runs Qdrant on Cloudron with a secure, two-surface topology on a single domain:

- The web dashboard (served under /dashboard) is placed behind Cloudron login, so only your
  Cloudron users can open the management UI.
- The REST and gRPC data plane stays in front of Cloudron login and is protected by Qdrant's own
  API key, so programmatic clients and sibling apps authenticate with a key rather than being
  redirected to an interactive sign-in page.

Qdrant is insecure by default: its API is open to anyone who can reach it. This package closes
that gap. It generates a strong admin key and a separate read-only key on first start, enables
JWT and role-based access control so you can mint scoped tokens, disables telemetry, refuses
snapshot recovery from arbitrary URLs, and configures Qdrant to reject writes rather than be
killed when it approaches its memory limit.

All persistent state lives under the application data directory, so Cloudron's backup covers it.

This is a community package. It tracks upstream Qdrant releases and keeps the upstream binary
unmodified. Qdrant and the Qdrant name and logo are trademarks of their respective owner. This
package is community-maintained and is not affiliated with or endorsed by the Qdrant project.
