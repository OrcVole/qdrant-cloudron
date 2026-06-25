#!/bin/bash
#
# Update-survival gate. Seed data, simulate an operator config edit, run `cloudron update`, and
# assert that the data and the operator edit both survive and take effect, and the app stays healthy.
#
# For a real cross-version test, install the prior package version first, then point this at the app
# and run it after switching the source to the new version.
#
# Usage: APP=qdrant.example.com ./upgrade.sh
set -uo pipefail

APP="${APP:?set APP to the app location}"
BASE="https://${APP}"
HERE="$(dirname "$0")"
K="$(cloudron exec --app "$APP" -- sh -c '. /app/data/.secrets/keys.env && printf %s "$QDRANT_ADMIN_API_KEY"' 2>/dev/null)"

echo "== seed known data =="
QDRANT_BASE="$BASE" QDRANT_KEY="$K" bash -c "source '${HERE}/lib.sh'; seed_known_data"

echo "== simulate operator edit (strict-mode 85 -> 70) =="
cloudron exec --app "$APP" -- sed -i 's/max_resident_memory_percent: 85/max_resident_memory_percent: 70/' /app/data/config/production.yaml

echo "== cloudron update (rebuilds from source, takes a backup first) =="
cloudron update --app "$APP"

echo "== verify survival =="
QDRANT_BASE="$BASE" QDRANT_KEY="$K" bash -c "source '${HERE}/lib.sh'; verify_known_data" \
  && echo "  PASS  data survived the update" || echo "  FAIL  data did not survive"
echo "  operator config (expect 70, not reseeded):"
cloudron exec --app "$APP" -- grep -n 'max_resident_memory_percent:' /app/data/config/production.yaml
echo "  new collection inherits the edited value (expect 70):"
curl -s -X PUT "$BASE/collections/upg_check" -H "api-key: $K" -H 'content-type: application/json' \
  -d '{"vectors":{"size":4,"distance":"Cosine"}}' >/dev/null
curl -s "$BASE/collections/upg_check" -H "api-key: $K" | grep -o '"strict_mode_config":{[^}]*}'; echo
curl -s -X DELETE "$BASE/collections/upg_check" -H "api-key: $K" >/dev/null
curl -s -o /dev/null -w '  GET /healthz -> %{http_code}\n' "$BASE/healthz"
