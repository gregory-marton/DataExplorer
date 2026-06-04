"""Tests for the deferred-integration runner's single-flight + supersede logic.

These exercise scripts/run_integration_deferred.sh in an isolated DI_ROOT with
DI_SLEEP=0 and a stub DI_CMD, so no real (slow) suite runs.
"""
import os
import stat
import subprocess
from pathlib import Path

from conftest import ROOT

SCRIPT = ROOT / "scripts" / "run_integration_deferred.sh"


def _env(tmp_path: Path, uuid: str, cmd_body: str) -> dict:
    """Isolated DI_ROOT with a sentinel and a stub DI_CMD; returns the env."""
    (tmp_path / ".cache").mkdir()
    (tmp_path / ".cache" / "integration_sentinel.txt").write_text(uuid)
    cmd = tmp_path / "cmd.sh"
    cmd.write_text(f"#!/usr/bin/env bash\n{cmd_body}\n")
    cmd.chmod(cmd.stat().st_mode | stat.S_IEXEC)
    return {
        **os.environ,
        "DI_ROOT": str(tmp_path),
        "DI_SLEEP": "0",
        "DI_CMD": str(cmd),
    }


def test_di_runner_single_flight(tmp_path):
    # Two concurrent runners with a matching sentinel: the lock must let only one
    # actually run DI_CMD (no overlapping integration runs).
    uuid = "uuid-single-flight"
    marker = tmp_path / "ran.log"
    env = _env(tmp_path, uuid, f'echo ran >> "{marker}"\nsleep 2')
    p1 = subprocess.Popen(["bash", str(SCRIPT), uuid], env=env)
    p2 = subprocess.Popen(["bash", str(SCRIPT), uuid], env=env)
    p1.wait(timeout=30)
    p2.wait(timeout=30)
    ran = marker.read_text().count("ran") if marker.exists() else 0
    assert ran == 1, f"single-flight lock should let exactly one DI run, got {ran}"


def test_di_runner_supersede_on_stale_uuid(tmp_path):
    # A runner whose UUID no longer matches the sentinel (a newer smoke run
    # superseded it) must not run at all.
    marker = tmp_path / "ran.log"
    env = _env(tmp_path, "current-uuid", f'echo ran >> "{marker}"')
    subprocess.run(["bash", str(SCRIPT), "stale-uuid"], env=env, timeout=30)
    assert not marker.exists(), "a superseded (stale-uuid) runner must not run DI_CMD"


def test_di_runner_passing_run_clears_sentinel(tmp_path):
    # A green run archives a passed file and clears the sentinel.
    uuid = "uuid-pass"
    marker = tmp_path / "ran.log"
    env = _env(tmp_path, uuid, f'echo ran >> "{marker}"')
    subprocess.run(["bash", str(SCRIPT), uuid], env=env, timeout=30)
    assert marker.exists() and marker.read_text().count("ran") == 1
    assert not (tmp_path / ".cache" / "integration_sentinel.txt").exists(), \
        "a passing run should clear the sentinel"
    passed = list((tmp_path / ".cache").glob("last_full_run_passed_*.txt"))
    assert passed, "a passing run should archive a last_full_run_passed_*.txt"
