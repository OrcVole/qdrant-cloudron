# Follow-on: packaging a Rust embedding service (TEI) for Cloudron

This is an outline for a separate, future package, not part of this repository's work. It is recorded
here because this Qdrant package is the vector-store half of a pure-Rust, Python-free retrieval stack,
and the embedding half is the natural next package.

## What and why

[HuggingFace text-embeddings-inference (TEI)](https://github.com/huggingface/text-embeddings-inference)
is a Rust embedding server built on tokio. It serves embeddings over HTTP and gRPC, exposes Prometheus
metrics and OpenTelemetry traces, and has Candle, ONNX, and Python backends. Packaging it as a sibling
Cloudron app completes the stack (Qdrant + TEI + rig + agentgateway) with no Ollama and no Python
needed for the core path. fastembed-rs is the in-process alternative when a separate service is not
wanted.

## Scope (roughly 40 hours)

The hard parts, none of which this Qdrant package had to solve:

- **Build story and glibc.** A CPU-only build on the Candle or ONNX backend is the simplest target
  and matches the cloudron/base glibc approach used here. A CUDA build pulls in the CUDA runtime and
  a GPU is rarely present on a Cloudron host, so default to CPU and document the GPU path separately.
  Run the same linkage gate this package uses (`ldd` plus a version check on the pinned base).
- **Model cache under /app/data.** TEI downloads model weights at first start. Point its cache
  (`HUGGINGFACE_HUB_CACHE` or the equivalent) at `/app/data` so the weights are persisted and backed
  up, and so the read-only root filesystem is respected. A first start with no cached model is slow;
  surface that in the post-install message.
- **The same two-surface auth decision.** TEI is mostly an API with a small docs or metrics surface.
  Apply the pattern from this package: keep the embedding API in front of Cloudron login behind its
  own credential so sibling apps can call it, and put any human surface behind proxyAuth. If TEI has
  no native API key, front it with the api_key pattern or rely on the network boundary plus a key
  injected by a thin layer.
- **Memory limits for model loading.** Embedding models are loaded into RAM. Size the default
  memoryLimit to the chosen model and document the relationship, mirroring this package's memory ADR.

## Shape

Mirror this package: a multi-stage Dockerfile copying the TEI binary onto `cloudron/base` pinned by
digest, a single source of the upstream version in a build argument, an entrypoint that prepares
`/app/data` and the model cache and drops privileges with gosu, a manifest with a health check and
the API exposed for sibling apps, and the same release gates (linkage, update survival, backup).

## Cross-links

- This Qdrant package is the vector-store counterpart. A TEI app embeds; this package stores and
  searches. See docs/INTEGRATIONS.md, section 3, for the combined stack.
- `config/examples/rig-qdrant.rs` and `config/examples/pure-rust-rag-stack.md` show how rig wires a
  Rust embedding provider to this package.
