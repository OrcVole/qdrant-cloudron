# 0003: Degrade, do not crash, under memory pressure

Status: accepted (verified on a live box, 2026-06-25)

## Context

Qdrant is memory-hungry: it keeps the HNSW graph and unquantized vectors in RAM by default. A
Cloudron memoryLimit that Qdrant ignored would lead to an out-of-memory kill and a restart loop,
which is worse than refusing work. Qdrant v1.18 added a cgroup-aware guard that the package can set
at boot.

## Decision

Ship, in the operator config, strict mode enabled with a resident-memory ceiling:

    storage:
      collection:
        strict_mode:
          enabled: true
          max_resident_memory_percent: 85
          max_disk_usage_percent: 90

`max_resident_memory_percent` is a percent of the container's cgroup memory limit, which Cloudron
sets from `memoryLimit`. When resident heap memory crosses the ceiling, Qdrant rejects writes
(upserts, set-payload) while continuing to serve reads and deletes, and stays alive. Pair it with
`on_disk_payload: true`, and document on-disk vectors, on-disk HNSW, and TurboQuant for fitting more
into RAM.

Set the default `memoryLimit` to 2 GB. The platform default of 256 MB is killed on the first real
collection.

## Consequences

- Under pressure the app refuses writes and stays up, rather than crash-looping.
- The guard counts the jemalloc heap, not the memory-mapped page cache, so once data is on disk it
  does not count toward the guard. For large collections, move vectors and the HNSW graph on disk so
  the heap guard is a backstop, not the only line.
- Strict mode applies to newly created collections. Pre-existing collections must be PATCHed to
  match. Verified on a live box: a collection created with the default config reports
  `max_resident_memory_percent: 85`; after an operator edit to 70, a collection created next reports
  70; and the 2 GB limit shows in the boot log as `cgroup memory.max=2147483648 bytes`.
- The guard is soft and samples every few seconds, so the percent is set below 100 to leave headroom.
