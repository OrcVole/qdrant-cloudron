#!/bin/bash
#
# Shared helpers for the live box tests (backup-restore and upgrade). Source this file.
#
# Required environment:
#   QDRANT_BASE   full base URL, for example https://qdrant.example.com
#   QDRANT_KEY    admin API key (from /app/data/.secrets/keys.env on the app)
#
# The data here is deliberately known and small so that survival across a backup or an update
# can be asserted exactly.

COLL="${QDRANT_TEST_COLLECTION:-survivetest}"

seed_known_data() {
  echo "  seeding collection '${COLL}' with 3 known points"
  curl -fsS -X PUT "${QDRANT_BASE}/collections/${COLL}" \
    -H "api-key: ${QDRANT_KEY}" -H 'content-type: application/json' \
    -d '{"vectors":{"size":4,"distance":"Dot"}}' >/dev/null
  curl -fsS -X PUT "${QDRANT_BASE}/collections/${COLL}/points?wait=true" \
    -H "api-key: ${QDRANT_KEY}" -H 'content-type: application/json' \
    -d '{"points":[
      {"id":1,"vector":[0.1,0.2,0.3,0.4],"payload":{"tag":"alpha","n":1}},
      {"id":2,"vector":[0.5,0.6,0.7,0.8],"payload":{"tag":"beta","n":2}},
      {"id":3,"vector":[0.9,0.1,0.2,0.3],"payload":{"tag":"gamma","n":3}}
    ]}' >/dev/null
}

# verify_known_data <expected-admin-key>
# Confirms the collection, point count, a known payload, and (if given) that the admin key that
# was generated before the backup still authenticates after the restore. Returns non-zero on any
# mismatch.
verify_known_data() {
  local expected_key="${1:-${QDRANT_KEY}}"
  local count payload strict ok=0

  count="$(curl -fsS "${QDRANT_BASE}/collections/${COLL}" -H "api-key: ${expected_key}" \
    | grep -o '"points_count":[0-9]*' | head -1)"
  payload="$(curl -fsS "${QDRANT_BASE}/collections/${COLL}/points/2" -H "api-key: ${expected_key}" \
    | grep -o '"tag":"[a-z]*"' | head -1)"
  strict="$(curl -fsS "${QDRANT_BASE}/collections/${COLL}" -H "api-key: ${expected_key}" \
    | grep -o '"strict_mode_config":{[^}]*}')"

  printf '  points: %s | payload(point2): %s\n' "${count:-MISSING}" "${payload:-MISSING}"
  printf '  strict_mode survived: %s\n' "${strict:-MISSING}"

  [ "${count}" = '"points_count":3' ] || { echo "  MISMATCH: expected 3 points"; ok=1; }
  [ "${payload}" = '"tag":"beta"' ]   || { echo "  MISMATCH: expected point 2 payload tag=beta"; ok=1; }
  return "${ok}"
}
