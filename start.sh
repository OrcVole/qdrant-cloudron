#!/bin/bash
#
# Cloudron entrypoint for Qdrant.
#
# Runs as root, prepares /app/data, generates and persists the API keys on first run, exports
# the package-forced settings as environment variables (which override the config files), then
# drops to the cloudron user and execs Qdrant. Every package-emitted line is prefixed with
# "==>" so logs are greppable. See docs/DEBUGGING.md for the boot ladder.

set -euo pipefail

CODE=/app/code
DATA=/app/data
BIN="${CODE}/qdrant"
SEED_TEMPLATE="${CODE}/config/production.yaml.template"
CONFIG_DIR="${DATA}/config"
CONFIG="${CONFIG_DIR}/production.yaml"
SECRETS_DIR="${DATA}/.secrets"
KEYS_ENV="${SECRETS_DIR}/keys.env"
SENTINEL="${DATA}/.initialized"
VERSION="${QDRANT_VERSION:-unknown}"

echo "==> [start] Qdrant ${VERSION} booting"

# 1. Ownership and layout. Backups and restores can reset ownership, so fix it before touching
#    anything else under /app/data. All persistent state lives here.
echo "==> [start] preparing ${DATA} (storage, snapshots, config, secrets)"
mkdir -p "${DATA}/storage" "${DATA}/snapshots" "${CONFIG_DIR}" "${SECRETS_DIR}"
chown -R cloudron:cloudron "${DATA}"
chmod 0700 "${SECRETS_DIR}"

# 2. First run only: generate the admin and read-only API keys. Never clobber an existing key
#    file; it is the user's data and rotating it would revoke their JWTs.
if [[ ! -f "${KEYS_ENV}" ]]; then
  echo "==> [start] first run: generating admin and read-only API keys"
  GEN_ADMIN="$(openssl rand -hex 32)"
  GEN_READONLY="$(openssl rand -hex 32)"
  ( umask 077; cat > "${KEYS_ENV}" <<EOF
# Qdrant API keys generated on first run. Treat both as secrets.
# QDRANT_ADMIN_API_KEY    : full read/write access.
# QDRANT_READONLY_API_KEY : read-only access.
# JWT/RBAC is enabled, so you can mint scoped tokens (signed by the admin key) from the
# dashboard "Access Tokens" panel. Rotating the admin key revokes every issued token.
QDRANT_ADMIN_API_KEY=${GEN_ADMIN}
QDRANT_READONLY_API_KEY=${GEN_READONLY}
EOF
  )
  chown cloudron:cloudron "${KEYS_ENV}"
  chmod 0600 "${KEYS_ENV}"
  unset GEN_ADMIN GEN_READONLY
  echo "==> [start] API keys stored at ${KEYS_ENV}"
else
  echo "==> [start] existing API keys found"
fi

# 3. First run only: seed the operator-tunable config from the baked template. Never overwrite
#    an existing config; the operator may have edited it.
if [[ ! -f "${CONFIG}" ]]; then
  echo "==> [start] first run: seeding operator config at ${CONFIG}"
  install -o cloudron -g cloudron -m 0640 "${SEED_TEMPLATE}" "${CONFIG}"
else
  echo "==> [start] existing operator config found at ${CONFIG}"
fi

touch "${SENTINEL}"
chown cloudron:cloudron "${SENTINEL}"

# 4. Load the generated keys, then export the package-forced settings. Environment variables
#    override every config file in Qdrant, so these always win regardless of operator edits:
#    storage stays under /app/data (so it is backed up), the keys are injected from the secret
#    file rather than written into the operator config, and the ports match the manifest.
# shellcheck disable=SC1090,SC1091
set -a; . "${KEYS_ENV}"; set +a

export QDRANT__SERVICE__HOST=0.0.0.0
export QDRANT__SERVICE__HTTP_PORT=6333
export QDRANT__SERVICE__GRPC_PORT=6334
export QDRANT__SERVICE__API_KEY="${QDRANT_ADMIN_API_KEY}"
export QDRANT__SERVICE__READ_ONLY_API_KEY="${QDRANT_READONLY_API_KEY}"
export QDRANT__STORAGE__STORAGE_PATH=/app/data/storage
export QDRANT__STORAGE__SNAPSHOTS_PATH=/app/data/snapshots

# 5. Informational: the real memory guard is strict_mode.max_resident_memory_percent in the
#    config, expressed as a percent of the cgroup limit Cloudron sets. Log the limit for
#    debuggability; do not act on it here.
if [[ -r /sys/fs/cgroup/memory.max ]]; then
  echo "==> [start] cgroup memory.max=$(cat /sys/fs/cgroup/memory.max) bytes"
fi

# 6. Report resolved runtime facts (never secrets) and hand off.
echo "==> [start] version  : ${VERSION}"
echo "==> [start] http     : 0.0.0.0:6333 (REST, dashboard at /dashboard, /metrics)"
echo "==> [start] grpc     : 0.0.0.0:6334"
echo "==> [start] storage  : ${QDRANT__STORAGE__STORAGE_PATH}"
echo "==> [start] snapshots: ${QDRANT__STORAGE__SNAPSHOTS_PATH}"
echo "==> [start] config   : ${CONFIG} (operator-tunable; environment overrides it)"
echo "==> [start] api keys : $( [[ -s "${KEYS_ENV}" ]] && echo 'admin + read-only present' || echo 'MISSING' )"

# 7. Working directory. Qdrant resolves ./static (the dashboard) and ./config/*.yaml relative
#    to the working directory, and writes a small init marker (.qdrant-initialized) into it.
#    /app/code is read-only, so run from a writable directory under /run and link the read-only
#    assets into it. This keeps every Qdrant write inside an allowed path. RUN_MODE=production
#    makes Qdrant read config/production.yaml (the operator file, linked below) as the overlay
#    above config/config.yaml, which also silences the "config/development not found" notice.
RUNDIR=/run/qdrant
mkdir -p "${RUNDIR}/config"
ln -sfn "${CODE}/static" "${RUNDIR}/static"
ln -sf "${CODE}/config/config.yaml" "${RUNDIR}/config/config.yaml"
ln -sf "${CONFIG}" "${RUNDIR}/config/production.yaml"
chown cloudron:cloudron "${RUNDIR}" "${RUNDIR}/config"
export RUN_MODE=production
cd "${RUNDIR}"

echo "==> [start] workdir  : ${RUNDIR} (RUN_MODE=production)"
echo "==> [start] exec qdrant ${VERSION}"
exec gosu cloudron:cloudron "${BIN}"
