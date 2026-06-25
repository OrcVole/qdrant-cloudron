#!/bin/bash
#
# Diagnostic: io_uring under the container seccomp profile.
#
# Qdrant can use io_uring for the async scorer (quantized multi-vector rescoring), but this package
# leaves it OFF (storage.performance.async_scorer defaults to false), because Docker's default
# seccomp profile commonly restricts io_uring syscalls and there is no confirmed graceful fallback.
#
# Run it inside the app container, for example:
#   cloudron exec --app qdrant.example.com -- bash -s < test/io_uring-check.sh

set -uo pipefail

echo "== seccomp posture of PID 1 =="
if [ -r /proc/1/status ]; then
  s="$(grep '^Seccomp:' /proc/1/status | tr -dc '0-9')"
  case "${s:-}" in
    2) echo "Seccomp: 2 (filter mode active). io_uring syscalls are likely restricted. Keep async_scorer off." ;;
    0) echo "Seccomp: 0 (disabled). io_uring may be available, but still verify under real load." ;;
    *) echo "Seccomp: ${s:-unknown}" ;;
  esac
else
  echo "cannot read /proc/1/status"
fi

echo "== async_scorer is off by default =="
echo "To try io_uring: set 'storage.performance.async_scorer: true' in"
echo "/app/data/config/production.yaml, restart, run a quantized multi-vector search, and watch the"
echo "logs for io_uring errors. Do not depend on it for correctness; it is only an opportunistic"
echo "speedup, and on a seccomp-filtered container it may not engage at all."
