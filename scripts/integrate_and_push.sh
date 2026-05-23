#!/usr/bin/env bash
# integrate_and_push.sh — run the full test suite in the sandbox worktree,
# then push to origin/main if green.
#
# Usage:
#   scripts/integrate_and_push.sh            # test + push
#   scripts/integrate_and_push.sh --dry-run  # test only, print what would be pushed
#
# The sandbox is a detached-HEAD git worktree at ../DataExplorer-sandbox.
# Create it once with:
#   git worktree add --detach ../DataExplorer-sandbox HEAD

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$REPO/../DataExplorer-sandbox"

if [ ! -d "$SANDBOX/.git" ] && [ ! -f "$SANDBOX/.git" ]; then
    echo "error: sandbox not found at $SANDBOX" >&2
    echo "  Create it with:" >&2
    echo "    git -C '$REPO' worktree add --detach ../DataExplorer-sandbox HEAD" >&2
    exit 1
fi

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

TARGET=$(git -C "$REPO" rev-parse main)
SUMMARY=$(git -C "$REPO" log --oneline -1 main)

echo "==> Syncing sandbox to: $SUMMARY"
git -C "$SANDBOX" checkout --detach "$TARGET" --quiet

echo "==> Running integration suite in sandbox…"
python3 -m pytest "$SANDBOX/tests/" -m slow --tb=short --rootdir="$SANDBOX"

if [[ $DRY_RUN -eq 1 ]]; then
    echo "==> [dry-run] would push $TARGET to origin/main"
else
    echo "==> Pushing to origin/main"
    git -C "$SANDBOX" push origin HEAD:main
    echo "==> Done."
fi
