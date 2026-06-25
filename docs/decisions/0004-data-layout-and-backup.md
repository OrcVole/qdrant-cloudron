# 0004: All state under /app/data, and the backup consistency model

Status: accepted (verified end to end on a live box, 2026-06-25)

## Context

Cloudron backs up only /app/data (plus addon databases), as a live copy taken while the app runs; it
does not stop the app. Qdrant under /app/data is a file store with a write-ahead log. A `backupCommand`
exists but runs in a separate temporary container with the app image and cannot quiesce the live
Qdrant, so it does not solve live-copy consistency.

## Decision

Put 100 percent of state under /app/data and force the paths there with environment variables so an
operator cannot move state out of the backup:

- `QDRANT__STORAGE__STORAGE_PATH=/app/data/storage`
- `QDRANT__STORAGE__SNAPSHOTS_PATH=/app/data/snapshots`
- the operator config at `/app/data/config/production.yaml`
- the API keys at `/app/data/.secrets/keys.env`

Do not use `persistentDirs`, `backupCommand`, or `restoreCommand`: everything is already under
/app/data, and those run in a separate container that cannot quiesce Qdrant. Rely on the live
/app/data copy plus Qdrant's write-ahead log, which replays on restore. Offer an opt-in in-container
snapshot cron (the scheduler addon, off by default) that writes a full Qdrant snapshot into
/app/data/snapshots for a transactionally consistent artifact.

## Consequences

- The Cloudron backup covers all state. Verified end to end on a live box: an app backup captured the
  storage (collections, segments, the write-ahead log) and the config, and a clone of that backup
  into a brand new app carried the data, the operator config, and the admin API key (byte-identical,
  so the same key authenticates on the restored app), with the app healthy.
- A live copy of a running datastore is crash-consistent, not transactionally consistent. The
  write-ahead log makes restore safe in practice; the optional snapshot cron is the belt-and-braces
  for the rare case that log recovery is insufficient.
- Ownership under /app/data is not preserved across backup and restore, so `start.sh` chowns it on
  every boot.
- Restore practicalities seen on the box: `cloudron clone` needs a pseudo-TTY (it prompts for a new
  gRPC host port when the source's is taken), and on a box with several backup sites, `--backup
  latest` may not resolve, so use a concrete id from `cloudron backup list`.
