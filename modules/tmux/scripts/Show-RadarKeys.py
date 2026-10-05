#!/usr/bin/env python3
"""Shows a radar pane's keys, rendered from its KEYS.md. Runs inside a tmux
popup, launched by radar_ui.show_keys when ? is pressed in the Git or Agents
pane.

Usage, as the command of a display-popup (through Invoke-Popup.sh):
  Show-RadarKeys.py <keys.md>

Renders only the markdown those files use -- `#` title, `##` sections, prose,
two-column `| key | does |` tables and `code` spans -- and renders it tight: a
general renderer (rich, glow) spends a blank line or three around every heading
and table, which pushed the Git pane's list past a screen. Key columns line up
across sections, so the list reads as one table. Any key closes it; a list
taller than the popup goes through `less -R` instead, which q closes.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import termios
import tty

BOLD = "\033[1m"
DIM = "\033[2m"
TITLE = "\033[1;36m"
SECTION = "\033[1;33m"
KEY = "\033[1;32m"
CODE = "\033[36m"
RESET = "\033[0m"

CODE_SPAN = re.compile(r"`([^`]+)`")
RULE_ROW = re.compile(r"^\|[\s:|-]+\|$")


def cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def plain(text: str) -> str:
    return CODE_SPAN.sub(r"\1", text)


def styled(text: str, base: str = "") -> str:
    """`code` spans coloured, the rest in `base`."""
    return base + CODE_SPAN.sub(lambda m: CODE + m.group(1) + RESET + base, text) + RESET


def render(text: str) -> str:
    lines = text.splitlines()
    # Table rows, minus each table's header and |---| rule.
    rows: list[tuple[str, str]] = []
    in_table = False
    for line in lines:
        if line.startswith("|"):
            if in_table and not RULE_ROW.match(line):
                key, does = (cells(line) + ["", ""])[:2]
                rows.append((key, does))
            in_table = True
        else:
            in_table = False
    width = max((len(plain(key)) for key, _ in rows), default=0)

    out: list[str] = []
    in_table = False
    # A section's heading sits on its first row, with no gap between.
    after_heading = False
    for line in lines:
        if line.startswith("|"):
            if in_table and not RULE_ROW.match(line):
                key, does = (cells(line) + ["", ""])[:2]
                pad = " " * (width - len(plain(key)))
                out.append(f"   {KEY}{plain(key)}{RESET}{pad}   {styled(does)}")
            in_table = True
            after_heading = False
            continue
        in_table = False
        if after_heading and not line.strip():
            continue
        after_heading = line.startswith("## ")
        if line.startswith("## "):
            if out and out[-1]:
                out.append("")
            out.append(f" {SECTION}{line[3:]}{RESET}")
        elif line.startswith("# "):
            out.append(f" {TITLE}{line[2:]}{RESET}")
        elif line.strip():
            out.append(f" {styled(line, DIM)}")
        elif out and out[-1]:
            # Blank lines only where the file separates prose, never doubled.
            out.append("")
    while out and not out[-1]:
        out.pop()
    return "\n".join(out) + "\n"


def size(text: str) -> tuple[int, int]:
    """The popup that fits `text` rendered: its prompt and border included."""
    rendered = render(text).splitlines()
    width = max((len(re.sub(r"\033\[[0-9;]*m", "", line)) for line in rendered), default=0)
    return width + 4, len(rendered) + 4


def wait_for_key() -> None:
    sys.stdout.write(f"\n {DIM}Press any key to close...{RESET}")
    sys.stdout.flush()
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        os.read(fd, 1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as handle:
        output = render(handle.read())

    _, height = shutil.get_terminal_size()
    # Two lines kept for the "press any key" prompt.
    if output.count("\n") > height - 2:
        subprocess.run(["less", "-R"], input=output, text=True, check=False)
        return 0
    sys.stdout.write(output)
    wait_for_key()
    return 0


if __name__ == "__main__":
    sys.exit(main())
