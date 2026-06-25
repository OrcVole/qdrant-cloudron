// Use this Qdrant package as the vector store for the rig agent framework (rig-qdrant), over gRPC.
//
// This is the primary reason the package exposes a gRPC TCP port. The client connects to the
// Cloudron gRPC host and port with the API key. The channel is plaintext (the TCP port is not
// TLS-terminated by Cloudron), so run it over a trusted network or a tunnel.
//
// rig is pre-1.0 and its API changes; pin and check these crates against their current releases.
// Cargo.toml (illustrative pins):
//   rig-core     = "0.36"
//   rig-qdrant   = "0.36"
//   qdrant-client = "1.15"
//   tokio        = { version = "1.47", features = ["full"] }
//   anyhow       = "1"

use qdrant_client::Qdrant;
use qdrant_client::qdrant::{CreateCollectionBuilder, Distance, VectorParamsBuilder};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Host and port shown for the app's "Qdrant gRPC API" port. The api_key is in
    // /app/data/.secrets/keys.env (read it with `cloudron exec`); pass it through the environment.
    let client = Qdrant::from_url("http://qdrant.example.com:6334")
        .api_key(std::env::var("QDRANT_API_KEY")?)
        .build()?;

    // Size the collection to your embedding model (for example 768 for many TEI models).
    let collection = "documents";
    if !client.collection_exists(collection).await? {
        client
            .create_collection(
                CreateCollectionBuilder::new(collection)
                    .vectors_config(VectorParamsBuilder::new(768, Distance::Cosine)),
            )
            .await?;
    }

    // From here, build a rig_qdrant::QdrantVectorStore around `client` and your rig embedding model
    // (a Rust embedding provider such as TEI or fastembed-rs; see docs/FOLLOWON-TEI.md), then use it
    // as a rig vector store for retrieval-augmented generation. Check the exact rig-qdrant
    // constructor against the version you pin, as it changes across pre-1.0 releases.
    println!("connected to Qdrant over gRPC; collection '{collection}' ready");
    Ok(())
}
