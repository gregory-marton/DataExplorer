#!/usr/bin/env bash
# Deferred integration runner.
# Usage: run_integration_deferred.sh <uuid>
# Launched by conftest.py after a successful smoke run. Sleeps 15 minutes,
# then checks that the sentinel UUID still matches before running the full suite.
#
# Live output: streamed to deferred_integration.log (tail -f friendly).
# On failure:  overwrites .cache/last_full_run.txt with this run only.
# On success:  archives to .cache/last_full_run_passed_<timestamp>.txt.

set -uo pipefail

UUID="${1:?UUID argument required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SENTINEL="$ROOT/.cache/integration_sentinel.txt"
LAST_RUN="$ROOT/.cache/last_full_run.txt"
LIVE_LOG="$ROOT/deferred_integration.log"

sleep 900

# Check sentinel is still ours — a newer smoke run would have written a new UUID
if [ ! -f "$SENTINEL" ] || [ "$(cat "$SENTINEL")" != "$UUID" ]; then
    exit 0
fi

cd "$ROOT"
TMPOUT=$(mktemp)

printf '\n=== DI run started: %s ===\n' "$(date)" >> "$LIVE_LOG"
printf '\a'

# Stream to live log in real-time; capture a copy in TMPOUT for .cache/ bookkeeping
if python3 -m pytest tests/ --override-ini="addopts=" --tb=short -v 2>&1 | tee -a "$LIVE_LOG" > "$TMPOUT"; then
    TS=$(date +%Y%m%d_%H%M%S)
    { printf '=== %s ===\n' "$(date)"; cat "$TMPOUT"; printf '\n'; } > "$ROOT/.cache/last_full_run_passed_${TS}.txt"
    rm -f "$SENTINEL" "$LAST_RUN"
    printf '=== DI run PASSED: %s ===\n' "$(date)" >> "$LIVE_LOG"
    printf '\a'
else
    # Overwrite (not append) so conftest always shows only the latest failed run
    { printf '=== %s ===\n' "$(date)"; cat "$TMPOUT"; printf '\n'; } > "$LAST_RUN"
    printf '=== DI run FAILED: %s ===\n' "$(date)" >> "$LIVE_LOG"
    printf '\a'
fi
rm -f "$TMPOUT"
