# Integrations

How this Qdrant package connects to the other software you are likely to run on the same Cloudron,
and how to avoid the problems that come from Cloudron's app isolation model.

Read AGENTS.md for the package rules. This file is about wiring Qdrant to its neighbours. Each recipe
is marked as verified live (exercised against the real app) or verified by config (the underlying
Qdrant path is proven, but the named client was not driven on the test box, usually to avoid
disturbing a production sibling).

## 1. Mental model: Qdrant is the vector store

Qdrant is a backend that other things read from and write to. Because the data plane is never behind
Cloudron single sign-on (see docs/decisions/0001), any client reaches Qdrant on its public domain
with the API key:

- REST over HTTPS: `https://qdrant.example.com`, key as the `api-key` header or `Authorization:
  Bearer`.
- gRPC over the TCP port: `qdrant.example.com:<port>`, same key, plaintext channel.

Mint a scoped, read-only or per-collection JWT in the dashboard "Access Tokens" panel to give each
client least privilege instead of the admin key.

## 2. The Cloudron networking model (read this before anything breaks)

**Cloudron apps are isolated containers.** Inside one app, `localhost` is that app, not another app.
A client app reaching Qdrant on `localhost:6333` will not find it.

**Use public domains for app-to-app traffic.** The supported way for one Cloudron app to reach
another is the other app's public HTTPS domain, for example `https://qdrant.example.com`. It is
stable across restarts and TLS terminated. Do not hardcode internal container IPs; they change.

**Each backend keeps its own credentials.** Store the Qdrant key in the consuming app's environment
and reference it there, rather than pasting it into a config file a UI might rewrite.

## 3. Headline: the pure-Rust, Python-free RAG stack

The reason this package exists is to be the vector store for a self-hostable, Python-free retrieval
stack where every component is Rust on tokio:

```
Ingest:      lopdf / the `pdf` crate to parse, pdf-extract or pdf_oxide for robust text extraction
Embed:       text-embeddings-inference (TEI) or fastembed-rs  (Candle / ONNX, Rust)
Store:       THIS Qdrant package, via rig-qdrant over gRPC + api_key
Orchestrate: rig (rig.rs), with TEI or fastembed as the embedding provider
Front:       agentgateway, exposing Qdrant's tools over MCP and routing LLM traffic
Runtime:     tokio, shared by Qdrant, rig, agentgateway, and TEI
```

PDF note: lopdf and the `pdf` crate are low-level parsers (lopdf's own text extraction is basic, with
roughly 80 percent real-world success), so use pdf-extract or pdf_oxide for ingestion. pdfium-render
is the most accurate but adds a C dependency (around 20 MB) and reintroduces a glibc and linker
concern.

Verified live: the embed-then-store-then-search core of this stack. fastembed (BAAI/bge-small-en,
384 dimensions) embedded three documents, this package stored them over REST with the key, and a
semantic query returned the correct document (score 0.74). The TEI embedding service is the planned
Rust-native counterpart to this package (see docs/FOLLOWON-TEI.md); fastembed-rs is the in-process
alternative.

See `config/examples/rig-qdrant.rs` and `config/examples/pure-rust-rag-stack.md`.

## 4. Tier-1 consumers

### agentgateway (sibling Cloudron app, the spine)

agentgateway exposes Qdrant to agents as MCP tools and routes LLM traffic. Run the official
`mcp-server-qdrant` as a stdio MCP backend inside agentgateway (it bundles `uvx`), pointed at this
Qdrant app's public domain with the key. See `config/examples/agentgateway-qdrant-mcp.yaml`.

Verified by config: the Qdrant side (REST and gRPC with the key) is proven live; the route was not
added to the test box's production agentgateway, because that would reconfigure a sibling app. The
example mirrors the agentgateway package's own working `qdrant-mcp.yaml`.

### n8n

n8n (2.x) has a built-in Qdrant Vector Store node and an official community node; both use a
`QdrantApi` credential that is a URL plus an API key over REST. See `config/examples/n8n-qdrant.md`.

Verified live at the Qdrant boundary: the REST plus `api-key` path the node uses (insert and
retrieve with the key returns 200, without it returns 401). The n8n node itself was not driven on the
test box.

### OpenWebUI

Set `VECTOR_DB=qdrant`, `QDRANT_URI=https://qdrant.example.com`, `QDRANT_API_KEY`, and
`ENABLE_QDRANT_MULTITENANCY_MODE=true` for a shared instance. See `config/examples/openwebui.env`.

Verified by config; the REST plus key path is proven live. OpenWebUI can drive Qdrant to high memory
use; this package's memory guard rejects writes rather than being killed, but raise the memory limit
or move vectors on disk for large knowledge bases. Do not repoint an OpenWebUI that already has a
vector store configured without a migration plan.

### rig (rig.rs)

`rig-qdrant` connects with `Qdrant::from_url(<grpc>:6334)` plus the key. This is the primary reason
the gRPC TCP port exists. TEI and Ollama are rig embedding providers. See
`config/examples/rig-qdrant.rs`.

Verified live at the gRPC boundary: `qdrant.Qdrant/HealthCheck` with the key returns the version
reply, gRPC reflection is enabled, and without the key the call is Unauthenticated. The rig client
library itself was not built on the test box.

### AnythingLLM

AnythingLLM supports Qdrant as a vector store and also exposes its workspaces over MCP. Point it at
`https://qdrant.example.com` with the key. Verified by config; the REST plus key path is proven live.

## 5. Tier-2 adjacent (document, do not overclaim)

- **TEI and Ollama** are embedding and LLM providers, not Qdrant clients. The vector link is through
  client code or a frontend, never provider to Qdrant directly. TEI is the pure-Rust default;
  Ollama is the alternative (on the test box Ollama required its own API key, so its recipe is
  config-verified only).
- **LibreChat** is not a Qdrant vector-store consumer; its RAG API is pgvector-native. Position
  Qdrant only as a tool for LibreChat's agents through agentgateway and MCP. Do not write a
  "LibreChat RAG on Qdrant" recipe.
- **rustfs** (S3-compatible, pre-production) is a complementary store for the source documents that
  get vectorised into Qdrant, not a storage backend for Qdrant (Qdrant is local-disk). It ships its
  own MCP server, so it can be federated alongside Qdrant behind agentgateway. Do not claim native S3
  snapshot upload unless verified.
- **Baserow** is an app-layer data source whose rows are vectorised into Qdrant through n8n.

## 6. Testing an integration

1. Reachability: from the client, `curl https://qdrant.example.com/healthz` (200) and
   `curl https://qdrant.example.com/collections -H "api-key: <key>"` (200 with the key, 401 without).
2. Through the client: have the client write and read a small collection, and confirm it appears in
   `GET /collections`.
3. Memory: for a heavy client, watch that writes are rejected rather than the app being killed under
   load, and raise the limit or move vectors on disk as needed.

Record any new failure and its fix in docs/DEBUGGING.md.
