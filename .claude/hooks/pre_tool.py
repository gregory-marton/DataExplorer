#!/usr/bin/env python3
"""Pre-tool hook: block known anti-patterns before they reach the tool."""
import json
import re
import sys

data = json.load(sys.stdin)
tool = data.get('tool_name', '')
inp  = data.get('tool_input', {})

# ── 1. grep/cat/head/tail on a specific .m file ──────────────────────────────
# Reading a known file with Bash bypasses the Read tool and triggers permission
# prompts. Use the Read tool (with offset/limit as needed) instead.
if tool == 'Bash':
    cmd = inp.get('command', '')
    if re.search(r'(^|\|)\s*\b(grep|cat|head|tail|awk|sed|perl|python)\b', cmd):
        # Block if a specific .m file path is present (no glob)
        if re.search(r'(?<!\*)\b[\w./\-]+\.(m|txt|log)\b(?!\*)', cmd):
            print(
                "HOOK blocked: Use the Read tool to read most files "
                "or write and execute an actual test or script to help you."
            )
            sys.exit(2)
    if re.search(r'matlab\s+-batch', cmd):
        if re.search(
            r'\b(checkcode|runtests|runTests|assert|verif[yi]|disp\s*\(|fprintf\s*\()',
            cmd
        ):
            print(
                "HOOK BLOCKED: write a pytest test instead of a matlab -batch one-liner. "
                "Run it with: python3 -m pytest tests/ -k <test_name>"
            )
            sys.exit(2)
    if re.search(r'pytest\b', cmd) and re.search(r'-m\s+slow', cmd):
        print(
            "HOOK BLOCKED: don't run -m slow explicitly. "
            "Use `python3 -m pytest tests/` (smoke only) during development; "
            "slow/integration tests run deferred in the background."
        )
        sys.exit(2)


# ── 2. Editing the off-limits scratch / student-examples files ───────────────
if tool in ('Edit', 'Write'):
    path = inp.get('file_path', '')
    for forbidden in ('student_examples.m', r'.claude/.*.py', '.git'):
        if re.match(forbidden, path):
            print(
                f"HOOK BLOCKED: {forbidden} is off-limits — "
                "never edit it directly. Paste snippets in chat only."
            )
            sys.exit(2)

# ── 3. New %#ok suppressors ───────────────────────────────────────────────────
# All suppressors were removed. Adding new ones re-introduces technical debt
# and will fail the checkcode test anyway.
if tool in ('Edit', 'Write'):
    content = inp.get('new_string', '') or inp.get('content', '')
    if '%#ok' in content:
        print(
            "HOOK BLOCKED: No new %#ok suppressors. "
            "Pre-allocate, restructure, or use the correct API instead."
        )
        sys.exit(2)

sys.exit(0)
