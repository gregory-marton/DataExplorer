#!/usr/bin/env bash
set -e
python3 "$(dirname "$0")/scripts/download_examples.py" "$@"
