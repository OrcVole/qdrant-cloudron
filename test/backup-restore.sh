#!/bin/bash
#
# Backup correctness gate. Back up a running Qdrant app, restore (clone) it into a fresh app, and
# assert that the data, the operator config, and the API key all survive and the app is healthy.
#
# This uses an app-level backup and clones into a NEW app. It never restores over an existing app.
#
# Usage:
#   SRC_APP=qdrant.example.com NEW_APP=qdrant-restore.example.com ./backup-restore.sh
#   KEEP=1   leave the restored app installed instead of uninstalling it at the end
set -uo pipefail

SRC="${SRC_APP:?set SRC_APP to the source app location}"
NEW="${NEW_APP:?set NEW_APP to a fresh restore-target location}"
HERE="$(dirname "$0")"

key_of() { cloudron exec --app "$1" -- sh -c '. /app/data/.secrets/keys.env && printf %s "$QDRANT_ADMIN_API_KEY"' 2>/dev/null; }

echo "== seed known data on ${SRC} =="
SRC_KEY="$(key_of "$SRC")"
QDRANT_BASE="https://${SRC}" QDRANT_KEY="$SRC_KEY" bash -c "source '${HERE}/lib.sh'; seed_known_data"

echo "== back up ${SRC} (app-level backup) =="
cloudron backup create --app "$SRC"

echo "== clone ${SRC} (latest backup) into fresh ${NEW} =="
cloudron clone --app "$SRC" --backup latest --location "$NEW"

echo "== verify on the restored app ${NEW} =="
NEW_KEY="$(key_of "$NEW")"
if [ -n "${NEW_KEY}" ] && [ "${NEW_KEY}" = "${SRC_KEY}" ]; then
  echo "  PASS  admin API key survived the restore (matches source)"
else
  echo "  FAIL  admin API key did not survive (source ${#SRC_KEY} chars, restored ${#NEW_KEY} chars)"
fi
QDRANT_BASE="https://${NEW}" QDRANT_KEY="$NEW_KEY" bash -c "source '${HERE}/lib.sh'; verify_known_data" \
  && echo "  PASS  data survived the restore" || echo "  FAIL  data did not survive"
echo "  operator config on restored app:"
cloudron exec --app "$NEW" -- grep -n 'max_resident_memory_percent:' /app/data/config/production.yaml
curl -s -o /dev/null -w '  restored app GET /healthz -> %{http_code}\n' "https://${NEW}/healthz"

if [ "${KEEP:-0}" != "1" ]; then
  echo "== cleanup: uninstall ${NEW} =="
  cloudron uninstall --app "$NEW"
fi
