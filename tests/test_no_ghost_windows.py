"""Guard against the ghost-window regression.

`figure(h)` on a *hidden* figure RAISES and SHOWS it — flashing a window during
headless/test runs even if visibility is reset a line later (the de_usamap bug).
Production code must make a figure current with `set(0,'CurrentFigure',h)`, which
leaves a hidden figure hidden.

This is a static check rather than a runtime one on purpose: the bug left the
figure hidden at the end, so an end-state visibility assertion would miss the
momentary flash.  The reliable signature is the source pattern itself.

Allowed:   figure('Name',...) / figure("Name",...) (creation), figure() , figure
Banned:    figure(fig) , figure(h) , figure(gcf) , figure(fig, ...)  (un-hide)
"""
import re
from pathlib import Path

from conftest import ROOT

PROD_FILES = sorted(f for f in ROOT.glob("*.m") if f.name != "student_examples.m")

# figure( <identifier> followed by ) or , — a handle, not a 'Name'/"Name" property
# and not part of "uifigure(".
BAN = re.compile(r"(?<![A-Za-z0-9_])figure\s*\(\s*[A-Za-z]\w*\s*[,)]")


def _strip_comment(line: str) -> str:
    if line.lstrip().startswith("%"):
        return ""
    return re.sub(r"%.*$", "", line)


def test_no_figure_handle_unhide():
    offenders = []
    for f in PROD_FILES:
        for i, line in enumerate(f.read_text().splitlines(), 1):
            if BAN.search(_strip_comment(line)):
                offenders.append(f"{f.name}:{i}: {line.strip()}")
    assert not offenders, (
        "figure(<handle>) un-hides a hidden figure (ghost window). "
        "Use set(0,'CurrentFigure',h) instead:\n" + "\n".join(offenders)
    )
