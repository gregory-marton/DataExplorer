#!/usr/bin/env bash
# Deferred integration runner.
# Usage: run_integration_deferred.sh <uuid>
# Launched by conftest.py after a successful smoke run. Sleeps 15 minutes,
# then checks that the sentinel UUID still matches before running the full suite.
# On failure: appends output to .cache/last_full_run.txt, leaves sentinel.
# On success: moves output to .cache/last_full_run_passed_<timestamp>.txt, deletes sentinel.

set -uo pipefail

UUID="${1:?UUID argument required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SENTINEL="$ROOT/.cache/integration_sentinel.txt"
LAST_RUN="$ROOT/.cache/last_full_run.txt"

sleep 900

# Check sentinel is still ours — a newer smoke run would have written a new UUID
if [ ! -f "$SENTINEL" ] || [ "$(cat "$SENTINEL")" != "$UUID" ]; then
    exit 0
fi

cd "$ROOT"
TMPOUT=$(mktemp)
if python3 -m pytest tests/ --tb=short > "$TMPOUT" 2>&1; then
    TS=$(date +%Y%m%d_%H%M%S)
    { printf '=== %s ===\n' "$(date)"; cat "$TMPOUT"; printf '\n'; } > "$ROOT/.cache/last_full_run_passed_${TS}.txt"
    rm -f "$SENTINEL" "$LAST_RUN"
else
    { printf '=== %s ===\n' "$(date)"; cat "$TMPOUT"; printf '\n'; } >> "$LAST_RUN"
fi
rm -f "$TMPOUT"
