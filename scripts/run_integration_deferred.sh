#!/usr/bin/env bash
# Deferred integration runner.
# Usage: run_integration_deferred.sh <uuid>
# Launched by conftest.py after a successful smoke run. Sleeps, then runs the full
# suite only if (a) the sentinel UUID still matches — a newer smoke run supersedes
# this one — and (b) no other DI is already running (single-flight lock), so runs
# never overlap.
#
# Live output: streamed to deferred_integration.log (tail -f friendly).
# On failure:  overwrites .cache/last_full_run.txt with this run only.
# On success:  archives to .cache/last_full_run_passed_<timestamp>.txt.
#
# Env overrides (for tests): DI_SLEEP (sleep seconds), DI_CMD (command to run).

set -uo pipefail

UUID="${1:?UUID argument required: pass 'now' to just launch it.}"
ROOT="${DI_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SENTINEL="$ROOT/.cache/integration_sentinel.txt"
LAST_RUN="$ROOT/.cache/last_full_run.txt"
LIVE_LOG="$ROOT/deferred_integration.log"
LOCKFILE="$ROOT/.cache/di.lock"

# Window long enough that ordinary dev pauses (edits, MATLAB probes) don't trip it;
# the deferred run is meant for genuine dry spells.  Overridable for tests.
SLEEP_SECS="${DI_SLEEP:-900}"
DI_CMD="${DI_CMD:-python3 -m pytest tests/ --override-ini=addopts= --tb=short -v}"
if [ "$UUID" == "now" ]; then
    UUID=$$
else
    sleep "$SLEEP_SECS"

    # Supersede: a newer smoke run would have written a new sentinel UUID.
    if [ ! -f "$SENTINEL" ] || [ "$(cat "$SENTINEL")" != "$UUID" ]; then
        exit 0
    fi
fi

# Single-flight: never let two DI runs overlap.  noclobber makes "> file" an
# atomic create-or-fail that also records the owner PID, so there is no window
# where the lock exists without an owner.  If the owner is alive, skip; if it is
# dead (a killed run), the lock is stale — steal it.
if ! ( set -o noclobber; echo "$$" > "$LOCKFILE" ) 2>/dev/null; then
    if kill -0 "$(cat "$LOCKFILE" 2>/dev/null)" 2>/dev/null; then
        exit 0
    fi
    rm -f "$LOCKFILE"
    ( set -o noclobber; echo "$$" > "$LOCKFILE" ) 2>/dev/null || exit 0
fi
trap 'rm -f "$LOCKFILE"' EXIT

cd "$ROOT"
TMPOUT=$(mktemp)

printf '\n=== DI run started: %s ===\n' "$(date)" >> "$LIVE_LOG"
printf '\a'

# Stream to live log in real-time; capture a copy in TMPOUT for .cache/ bookkeeping
if $DI_CMD 2>&1 | tee -a "$LIVE_LOG" > "$TMPOUT"; then
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
