#!/bin/bash
#
# Opt-in periodic snapshot task for Qdrant, run by the Cloudron scheduler addon.
#
# Disabled by default. Enable by setting the app environment variable QDRANT_SNAPSHOT_CRON to
# "enabled" in the Cloudron dashboard. When enabled, this creates a full storage snapshot into
# /app/data/snapshots (which is inside the Cloudron backup), giving a transactionally
# consistent artifact independent of the live-copy backup, and keeps the newest N snapshots.
#
# The PRIMARY backup path is the live /app/data copy plus WAL replay on restore (see
# docs/UPGRADING.md). This cron is belt-and-suspenders for the rare case that WAL recovery
# fails. Snapshots roughly double the on-disk size of the snapshotted data, so leave this off
# unless the data justifies it.

set -euo pipefail

if [[ "${QDRANT_SNAPSHOT_CRON:-disabled}" != "enabled" ]]; then
  echo "==> [snapshot] QDRANT_SNAPSHOT_CRON is not 'enabled'; skipping"
  exit 0
fi

KEYS_ENV=/app/data/.secrets/keys.env
RETAIN="${QDRANT_SNAPSHOT_RETAIN:-2}"
BASE="http://127.0.0.1:6333"

if [[ ! -r "${KEYS_ENV}" ]]; then
  echo "==> [snapshot] cannot read ${KEYS_ENV}; is the app initialized?" >&2
  exit 1
fi
# shellcheck disable=SC1090,SC1091
. "${KEYS_ENV}"

echo "==> [snapshot] creating full storage snapshot"
curl -fsS -X POST "${BASE}/snapshots" \
  -H "api-key: ${QDRANT_ADMIN_API_KEY}" \
  -H 'content-type: application/json' >/dev/null

# Prune to the newest ${RETAIN} full snapshots. Parse the snapshot list with Node (provided by
# the base image) to avoid adding a JSON tool to the runtime.
to_delete="$(curl -fsS "${BASE}/snapshots" -H "api-key: ${QDRANT_ADMIN_API_KEY}" \
  | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const names=(JSON.parse(s).result||[]).map(x=>x.name).sort();
  const keep=parseInt(process.env.RETAIN||"2",10);
  for(const n of names.slice(0,Math.max(0,names.length-keep))) console.log(n);
});' RETAIN="${RETAIN}")"

while IFS= read -r snap; do
  [[ -n "${snap}" ]] || continue
  echo "==> [snapshot] pruning ${snap}"
  curl -fsS -X DELETE "${BASE}/snapshots/${snap}" -H "api-key: ${QDRANT_ADMIN_API_KEY}" >/dev/null || true
done <<< "${to_delete}"

echo "==> [snapshot] done (retain=${RETAIN})"
