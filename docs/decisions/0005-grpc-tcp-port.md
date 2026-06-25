# 0005: Expose gRPC on a Cloudron TCP port

Status: accepted (verified on a live box, 2026-06-25)

## Context

Qdrant serves gRPC on port 6334, used by high-throughput clients, notably the Rust `rig-qdrant`
client, which is the primary reason this package exposes gRPC at all. Cloudron maps one HTTP port to
a domain with TLS, but gRPC is not plain HTTP, so it cannot share the dashboard domain. Cloudron's
mechanism for a non-HTTP port is a `tcpPort`, exposed on the box at a host port.

## Decision

Expose gRPC as a manifest `tcpPort` (container port 6334, defaultValue 6334, env var
`QDRANT_GRPC_PORT`). The same API key protects it: the package forces `QDRANT__SERVICE__GRPC_PORT=6334`
and Qdrant's api_key applies to gRPC as well as REST. Do not expose the p2p port 6335 (cluster mode is
disabled).

## Consequences

- Clients reach gRPC at `<host>:<port>`. Verified on a live box: `qdrant.Qdrant/HealthCheck` with the
  key returns the version reply; without the key it is `Unauthenticated`. gRPC reflection is enabled,
  so clients need no .proto file.
- A `tcpPort` is plain TCP and is not TLS-terminated by Cloudron, so the gRPC channel is plaintext on
  the wire. This is stated in the manifest port description and the README. Clients that need
  encryption use the REST API over the TLS domain, or tunnel the gRPC port.
- A Cloudflare-proxied domain proxies only HTTP and cannot forward a raw TCP port, so a host serving
  the gRPC port needs a DNS-only (grey-cloud) record. The test box domain was not proxied, so gRPC
  worked on the public domain directly.
- Choose a host port outside the Linux ephemeral range (32768 to 60999) to avoid collisions; the
  default is 6334.
