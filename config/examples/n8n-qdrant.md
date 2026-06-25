# n8n with this Qdrant package

n8n (2.x) has a built-in Qdrant Vector Store node, and there is an official community node
(`n8n-nodes-qdrant`, needs n8n 1.70 or newer). Both use a `QdrantApi` credential that is just a URL
and an API key over REST, which is exactly the path this package secures and which is verified
working (REST plus the `api-key` header).

## Credential (QdrantApi)

- Qdrant URL: `https://qdrant.example.com` (this app's domain, not `localhost`; Cloudron apps are
  isolated containers, so n8n must reach Qdrant on its public domain)
- API key: the admin key, or a scoped JWT minted in the dashboard "Access Tokens" panel for least
  privilege

## Insert and retrieve

- Use the Qdrant Vector Store node in insert mode to upsert embedded documents, and in
  retrieve-as-tool mode to back an AI Agent node. The node creates the collection if it is missing.
- Embed with a Rust embedding service (TEI or fastembed-rs) to keep the stack Python-free, or with
  any embedding node n8n offers.

The REST plus `api-key` path this node uses is verified live against this package: an insert and a
retrieve with the key return 200, and without the key the API returns Qdrant's own 401. The n8n node
itself was not exercised in this package's test box (it would require credentials on a production
n8n), so this recipe is verified at the Qdrant boundary, not through the n8n UI.
