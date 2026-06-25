# The pure-Rust, Python-free RAG stack

A self-hostable retrieval-augmented-generation stack where every component is Rust on tokio, with
this Qdrant package as the vector store. Each link is independent, so you can adopt as much as you
want.

```
PDF or text  --parse-->  text chunks  --embed-->  vectors  --store-->  Qdrant (this package)
                                                                          |
   agent query  --embed-->  query vector  --search-->  top-k chunks  -----+
                                                                          |
                                          rig builds the prompt  <--------+
                                          agentgateway fronts the agent and the LLM
```

## 1. Ingest (Rust)

Parse documents with `lopdf` or the `pdf` crate, and extract text with `pdf-extract` or `pdf_oxide`
(lopdf's own extraction is basic). `pdfium-render` is the most accurate but adds a C dependency and a
glibc and linker concern. Chunk the text for embedding.

## 2. Embed (Rust)

Use a Rust embedding service or library:

- text-embeddings-inference (TEI) as a sibling Cloudron app (see docs/FOLLOWON-TEI.md), called over
  HTTP or gRPC, or
- fastembed-rs in-process (Candle or ONNX), when a separate service is not wanted.

Both avoid Python. The embedding dimension sets the Qdrant collection's vector size (for example 384
for a small model, 768 for many TEI models).

## 3. Store and search (this Qdrant package)

Connect `rig-qdrant` to this package over gRPC with the API key (see `rig-qdrant.rs`). Create a
collection sized to the embedding model, upsert the document vectors with their text as payload, and
search with the query vector. For larger corpora, store vectors on disk and enable TurboQuant
quantization so more fits in RAM.

## 4. Orchestrate (rig)

`rig` builds the agent: it embeds the query through the same provider, searches Qdrant for the top-k
chunks, assembles the prompt, and calls the LLM. TEI or Ollama is the embedding provider; the LLM can
be Ollama, a local server, or a cloud provider.

## 5. Front (agentgateway)

agentgateway exposes the agent and Qdrant's tools over MCP and routes the LLM traffic with auth,
policies, and cost visibility. See `agentgateway-qdrant-mcp.yaml`.

## Runtime

Qdrant, rig, agentgateway, and TEI all run on tokio (the 1.x LTS line), so the stack shares one async
runtime model and no Python interpreter is in the core path.

## Verified

The embed-then-store-then-search core was exercised live against this package: fastembed embedded
three documents, this package stored them, and a semantic query returned the correct document. The
remaining links (rig, agentgateway, TEI) are wired by the example configs and are the subject of the
follow-on package work.
