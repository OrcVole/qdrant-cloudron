#!/bin/bash
#
# Verify the two-surface topology on a running Qdrant Cloudron install.
#
# This is the load-bearing security test for this package. It proves that the dashboard is
# behind Cloudron single sign-on while the REST and gRPC data plane is reachable directly and
# protected by Qdrant's own API key (so programmatic clients get Qdrant's native 401, not a
# login redirect).
#
# Usage:
#   QDRANT_DOMAIN=qdrant.example.com \
#   QDRANT_ADMIN_KEY=<admin key from /app/data/.secrets/keys.env> \
#   [QDRANT_GRPC=host:port] \
#   ./sso-topology.sh
#
# Exit code is non-zero if any assertion fails.

set -uo pipefail

DOMAIN="${QDRANT_DOMAIN:?set QDRANT_DOMAIN to the app domain, for example qdrant.example.com}"
KEY="${QDRANT_ADMIN_KEY:?set QDRANT_ADMIN_KEY to the admin API key}"
GRPC="${QDRANT_GRPC:-}"
BASE="https://${DOMAIN}"

pass=0
fail=0
ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "== 1. Dashboard is behind Cloudron single sign-on =="
# No session and no bearer token must redirect to the Cloudron login (a 3xx), never serve the UI.
dash_code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/dashboard")"
dash_loc="$(curl -s -o /dev/null -w '%{redirect_url}' "${BASE}/dashboard")"
case "${dash_code}" in
  30[0-9]) ok "GET /dashboard (no session) -> ${dash_code} redirect to ${dash_loc:-Cloudron login}" ;;
  *)       no "GET /dashboard (no session) -> ${dash_code} (expected a 3xx redirect to login)" ;;
esac

echo "== 2. Data plane returns Qdrant's own 401, not a login redirect =="
dp_code="$(code "${BASE}/collections")"
dp_body="$(curl -s "${BASE}/collections")"
case "${dp_code}" in
  401|403) ok "GET /collections (no key) -> ${dp_code}: ${dp_body}" ;;
  30[0-9]) no "GET /collections (no key) -> ${dp_code} REDIRECT (proxyAuth is wrongly in front of the data plane)" ;;
  *)       no "GET /collections (no key) -> ${dp_code} (expected Qdrant 401/403, got: ${dp_body})" ;;
esac

echo "== 3. Data plane accepts the API key =="
b_code="$(code -H "Authorization: Bearer ${KEY}" "${BASE}/collections")"
[ "${b_code}" = "200" ] && ok "GET /collections (Authorization: Bearer) -> 200" || no "GET /collections (Bearer) -> ${b_code}"
a_code="$(code -H "api-key: ${KEY}" "${BASE}/collections")"
[ "${a_code}" = "200" ] && ok "GET /collections (api-key header) -> 200" || no "GET /collections (api-key) -> ${a_code}"

echo "== 4. Health and metrics =="
h_code="$(code "${BASE}/healthz")"
[ "${h_code}" = "200" ] && ok "GET /healthz (no auth) -> 200" || no "GET /healthz -> ${h_code} (health must be an open 2xx)"

echo "== 5. gRPC data plane with the API key =="
if [ -n "${GRPC}" ]; then
  if command -v grpcurl >/dev/null 2>&1; then
    # The Cloudron TCP port is plain TCP (no TLS), so use -plaintext. Qdrant exposes gRPC
    # reflection, so no .proto file is needed.
    if grpcurl -plaintext -H "api-key: ${KEY}" "${GRPC}" qdrant.Qdrant/HealthCheck >/dev/null 2>&1; then
      ok "gRPC ${GRPC} qdrant.Qdrant/HealthCheck (api-key) -> ok"
    else
      no "gRPC ${GRPC} HealthCheck failed (check the host:port, plaintext, and that the domain is not Cloudflare-proxied)"
    fi
  else
    echo "  SKIP  grpcurl not installed; install it to exercise the gRPC assertion"
  fi
else
  echo "  SKIP  QDRANT_GRPC not set (host:port of the gRPC TCP port)"
fi

echo "== summary: ${pass} passed, ${fail} failed =="
[ "${fail}" -eq 0 ]
