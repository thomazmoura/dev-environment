#!/usr/bin/env python3
"""List, open and delete git worktrees, in a pane.

Bound to prefix+t then W (see modules/tmux/common.conf), which opens it through
New-ToolPane.sh in the pane's current path. It is the manager for the worktrees
prefix+t then w creates (New-Worktree.sh); the shell side of all of it --
registry, naming, removal -- is worktree-helpers.sh, and this defers to it for
anything that changes something.

Two scopes:
  repo  the default: every worktree of the repository this pane is in, as git
        itself lists them -- the main one, the ones prefix+t, w made, and any
        made some other way (Claude's --worktree, a plain `git worktree add`)
  all   every worktree in the registry (~/.worktrees), across repositories,
        plus the current repository's own list

Two lines per worktree, drawn with the same scaffolding as the radar feeds
(radar_ui.py): a marker coloured by state, the folder name and a dot when a
session is open on it; then its branch, its state and, in the all scope, the
repository it belongs to.

    blue    the main worktree
    green   clean
    yellow  uncommitted changes
    red     the folder is gone

It does not refresh on a timer. A worktree's state changes when you change it,
and every action here reloads the list afterwards; r reloads by hand.

Keys: j/k or the arrows move, g/G jump to the ends, / filters, a switches scope,
r reloads, Enter opens (switches to its session, or creates one with the
standard layout), d deletes after asking, q, Esc or Ctrl-C closes the pane.

The filter is a case-insensitive substring match on name, branch and path.
While typing, Enter keeps it and Esc drops it; with a filter set and no prompt
open, Esc clears it before it would close the pane.

Deleting asks first, in the pane, and the question is modal: y deletes and every
other key is a no. A dirty worktree says its changes will be lost -- d is the
deliberate way to throw them away; the session-closed hook never does. The
branch is deleted only when it is merged; see remove_worktree.

Usage: Show-Worktrees.py
"""

from __future__ import annotations

import curses
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import radar_ui as ui  # noqa: E402

NEW_SESSION = os.path.join(HERE, "New-CodeSession.sh")
REMOVE = os.path.join(HERE, "Remove-Worktree.sh")

# Same default and override as worktree-helpers.sh.
REGISTRY = os.environ.get("WORKTREE_REGISTRY") or os.path.expanduser("~/.worktrees")

MARKER = "●"
SESSION_DOT = "•"

MAIN = "main"
CLEAN = "clean"
DIRTY = "dirty"
MISSING = "missing"

STATE_COLOUR = {
    MAIN: curses.COLOR_BLUE,
    CLEAN: curses.COLOR_GREEN,
    DIRTY: curses.COLOR_YELLOW,
    MISSING: curses.COLOR_RED,
}

HINTS = "enter open · d delete · / filter · a scope · q quit"


@dataclass
class Worktree:
    path: str
    repo: str
    branch: str
    main: bool
    state: str = CLEAN
    session: bool = False

    @property
    def name(self) -> str:
        return os.path.basename(self.path)

    def matches(self, needle: str) -> bool:
        needle = needle.lower()
        return any(needle in field.lower() for field in (self.name, self.branch, self.path))


# --- Reading ------------------------------------------------------------------

def git(*argv: str, cwd: str | None = None) -> tuple[int, str]:
    try:
        result = subprocess.run(
            ["git", *argv],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return 1, ""
    return result.returncode, result.stdout


def repo_root(directory: str) -> str:
    """The main working tree of the repository `directory` is in, or "".

    The same question worktree-helpers.sh's repo_root answers, the same way: the
    parent of the shared .git directory, so a pane inside a worktree still
    resolves to the repository it came from.
    """
    code, out = git("-C", directory, "rev-parse", "--path-format=absolute", "--git-common-dir")
    common = out.strip()
    if code != 0 or not common:
        return ""
    return os.path.dirname(common)


def session_name(tree: Worktree) -> str:
    """Must stay in step with session_name_for in worktree-helpers.sh."""
    name = os.path.basename(tree.path)
    if not tree.main:
        name = f"{os.path.basename(tree.repo)}_{name}"
    return name.replace(".", "_")


def read_registry() -> list[tuple[str, str]]:
    try:
        with open(REGISTRY, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return []
    rows = []
    for line in lines:
        path, _, repo = line.partition("\t")
        if path:
            rows.append((path, repo))
    return rows


def git_worktrees(repo: str) -> list[Worktree]:
    """`git worktree list --porcelain`, main worktree first as git prints it."""
    code, out = git("-C", repo, "worktree", "list", "--porcelain")
    if code != 0:
        return []
    found: list[Worktree] = []
    for block in out.strip().split("\n\n"):
        path = branch = ""
        bare = False
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            if key == "worktree":
                path = value
            elif key == "branch":
                branch = value.removeprefix("refs/heads/")
            elif key == "bare":
                bare = True
        if path and not bare:
            found.append(Worktree(path, repo, branch, main=not found))
    return found


def branch_of(path: str) -> str:
    code, out = git("-C", path, "symbolic-ref", "--quiet", "--short", "HEAD")
    return out.strip() if code == 0 else ""


def open_sessions() -> set[str]:
    try:
        result = subprocess.run(
            ["tmux", "list-sessions", "-F", "#{session_name}"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    return set(result.stdout.splitlines()) if result.returncode == 0 else set()


def settle(tree: Worktree) -> Worktree:
    """Fill in what needs git to answer: state, and the branch of registry-only rows."""
    if not os.path.isdir(tree.path):
        tree.state = MISSING
        return tree
    if not tree.branch:
        tree.branch = branch_of(tree.path)
    code, out = git("-C", tree.path, "status", "--porcelain")
    if code == 0 and out.strip():
        tree.state = DIRTY
    else:
        tree.state = MAIN if tree.main else CLEAN
    return tree


def load(repo: str, everything: bool) -> list[Worktree]:
    trees: dict[str, Worktree] = {}
    if repo:
        for tree in git_worktrees(repo):
            trees[tree.path] = tree
    for path, owner in read_registry():
        if path in trees or not (everything or owner == repo):
            continue
        trees[path] = Worktree(path, owner, "", main=False)

    # One `git status` per row, which on a large repository is the slow part;
    # in parallel, so a dozen worktrees cost about as much as the slowest one.
    with ThreadPoolExecutor(max_workers=8) as pool:
        settled = list(pool.map(settle, trees.values()))

    sessions = open_sessions()
    for tree in settled:
        tree.session = session_name(tree) in sessions

    # Grouped by repository, the main worktree leading its group, then by name.
    return sorted(settled, key=lambda t: (t.repo, not t.main, t.name.lower()))


# --- Acting -------------------------------------------------------------------

def open_worktree(tree: Worktree) -> None:
    """Switch to the worktree's session, creating it with the layout if needed.

    New-CodeSession.sh already does exactly that, including the switch-client
    that works from inside a pane. stdin is closed so that its die(), which
    waits for a keypress, cannot sit reading this pane's keyboard.
    """
    subprocess.run(
        [NEW_SESSION, tree.path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def delete_worktree(tree: Worktree) -> str:
    """Run Remove-Worktree.sh and return what it said, on one line."""
    argv = [REMOVE, "--force", tree.path] if tree.state == DIRTY else [REMOVE, tree.path]
    try:
        result = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return f"delete failed: {error}"
    lines = [line.strip() for line in (result.stdout + result.stderr).splitlines() if line.strip()]
    return "; ".join(lines) or ("deleted" if result.returncode == 0 else "delete failed")


# --- Drawing ------------------------------------------------------------------

class View:
    def __init__(self, stdscr, repo: str) -> None:
        self.stdscr = stdscr
        self.repo = repo
        self.use_colour = curses.has_colors()
        self.palette, self.band, grey = ui.start_colour()
        self.grey = grey

    def colour(self, value: int, selected: bool = False, extra: int = 0) -> int:
        if not self.use_colour or self.palette is None:
            return extra | (self.band if selected else curses.A_NORMAL)
        attr = self.palette.attr(value, selected)
        if selected:
            attr |= curses.A_BOLD
        return attr | extra

    def dim(self, selected: bool = False) -> int:
        if self.grey is not None:
            return self.colour(self.grey, selected)
        return self.colour(-1, selected, curses.A_DIM)

    def header(self, width: int, everything: bool, shown: int, total: int) -> None:
        scope = "all" if everything else (os.path.basename(self.repo) or "no repository")
        count = f"{shown}" if shown == total else f"{shown}/{total}"
        ui.draw_line(
            self.stdscr, 0, width,
            [("worktrees · ", self.dim()), (scope, curses.A_BOLD), (f"  {count}", self.dim())],
        )

    def rows(self, trees: list[Worktree], selected: int, everything: bool,
             top: int, height: int, width: int) -> None:
        visible = max(1, height // ui.ROW_LINES)
        start = ui.window_start(selected, len(trees), visible)
        for offset, tree in enumerate(trees[start:start + visible]):
            chosen = start + offset == selected
            row = top + offset * ui.ROW_LINES
            fill = self.band if chosen else None
            first = [
                (MARKER + " ", self.colour(STATE_COLOUR[tree.state], chosen)),
                (ui.truncate(tree.name, width - 5), self.colour(-1, chosen, curses.A_BOLD)),
            ]
            if tree.session:
                first.append((" " + SESSION_DOT, self.colour(curses.COLOR_CYAN, chosen)))
            ui.draw_line(self.stdscr, row, width, first, fill)

            second = [(ui.INDENT, self.colour(-1, chosen))]
            second.append((tree.branch or "(detached)", self.colour(curses.COLOR_MAGENTA, chosen)))
            second.append((" · " + tree.state, self.colour(STATE_COLOUR[tree.state], chosen)
                           if tree.state != CLEAN else self.dim(chosen)))
            if everything:
                second.append((" · " + os.path.basename(tree.repo), self.dim(chosen)))
            ui.draw_line(self.stdscr, row + 1, width, second, fill)

    def footer(self, row: int, width: int, text: str, attr: int) -> None:
        ui.draw_line(self.stdscr, row, width, [(ui.truncate(text, width - 1), attr)])

    def confirm(self, tree: Worktree) -> None:
        """Take the whole pane for the question, as Watch-GitFeed.py's kill does."""
        self.stdscr.erase()
        height, width = self.stdscr.getmaxyx()
        red = self.colour(curses.COLOR_RED, extra=curses.A_BOLD)
        lines = [
            ("delete worktree", self.dim()),
            (tree.name, red),
            (tree.path, self.dim()),
        ]
        if tree.branch:
            lines.append((f"branch {tree.branch} (deleted only if merged)", curses.A_NORMAL))
        if tree.state == DIRTY:
            lines.append(("uncommitted changes will be lost", red))
        if tree.state == MISSING:
            lines.append(("folder is gone -- only its records go", curses.A_NORMAL))
        if tree.session:
            lines.append(("its session will be killed", self.colour(curses.COLOR_YELLOW)))
        lines += [("", curses.A_NORMAL), ("y  delete", red), ("n  cancel", curses.A_NORMAL)]
        for row, (text, attr) in enumerate(lines):
            if row >= height:
                break
            ui.add(self.stdscr, row, 0, ui.truncate(text, width - 1), attr)
        self.stdscr.refresh()


# --- Loop ---------------------------------------------------------------------

BACKSPACE = (curses.KEY_BACKSPACE, 127, 8)
ENTER = (curses.KEY_ENTER, 10, 13)
ESC = 27
CTRL_C = 3


def run(stdscr) -> None:
    curses.curs_set(0)
    # As in the feeds: Ctrl-C has to arrive as a key, not as SIGINT, or pwsh --
    # the pane's parent, see tmux-helpers.sh:pwsh_command -- dies with it and
    # leaves a shell behind instead of closing the pane.
    curses.raw()
    stdscr.keypad(True)

    repo = repo_root(os.getcwd())
    view = View(stdscr, repo)
    # With no repository under this pane there is nothing to scope to.
    everything = not repo
    trees = load(repo, everything)
    selected = 0
    needle = ""
    typing = False
    pending: Worktree | None = None
    note = ""

    def shown() -> list[Worktree]:
        return [t for t in trees if t.matches(needle)] if needle else trees

    def reload(anchor: str = "") -> None:
        nonlocal trees, selected
        trees = load(repo, everything)
        rows = shown()
        paths = [t.path for t in rows]
        if anchor in paths:
            selected = paths.index(anchor)
        selected = max(0, min(selected, len(rows) - 1))

    try:
        while True:
            rows = shown()
            selected = max(0, min(selected, len(rows) - 1))

            if pending is not None:
                view.confirm(pending)
            else:
                stdscr.erase()
                height, width = stdscr.getmaxyx()
                view.header(width, everything, len(rows), len(trees))
                body = max(1, height - 2)
                if rows:
                    view.rows(rows, selected, everything, 1, body, width)
                else:
                    empty = "no match" if needle else "no worktrees"
                    ui.add(stdscr, 1, 0, ui.truncate(empty, width - 1), view.dim())
                if typing:
                    view.footer(height - 1, width, "/" + needle, curses.A_BOLD)
                elif note:
                    view.footer(height - 1, width, note, view.colour(curses.COLOR_CYAN))
                elif needle:
                    view.footer(height - 1, width, f"/{needle}  (esc clears)", view.dim())
                else:
                    view.footer(height - 1, width, HINTS, view.dim())
                stdscr.refresh()

            key = stdscr.getch()
            if key == curses.KEY_RESIZE:
                continue

            if pending is not None:
                # Modal: only y deletes; every other key, Ctrl-C included, is no.
                if key in (ord("y"), ord("Y")):
                    note = delete_worktree(pending)
                    reload()
                pending = None
                continue

            if key == CTRL_C:
                return

            if typing:
                if key in ENTER:
                    typing = False
                elif key == ESC:
                    typing = False
                    needle = ""
                elif key in BACKSPACE:
                    needle = needle[:-1]
                elif key == curses.KEY_DOWN:
                    selected += 1
                elif key == curses.KEY_UP:
                    selected -= 1
                elif 32 <= key < 127:
                    needle += chr(key)
                    selected = 0
                continue

            note = ""
            if key in (ord("j"), curses.KEY_DOWN):
                selected += 1
            elif key in (ord("k"), curses.KEY_UP):
                selected -= 1
            elif key == ord("g"):
                selected = 0
            elif key == ord("G"):
                selected = len(rows) - 1
            elif key == ord("/"):
                typing = True
            elif key == ord("a"):
                if repo:
                    everything = not everything
                    reload(rows[selected].path if rows else "")
            elif key == ord("r"):
                reload(rows[selected].path if rows else "")
            elif key in ENTER:
                if rows:
                    tree = rows[selected]
                    if tree.state == MISSING:
                        note = f"{tree.name}: folder is gone -- d drops it"
                    else:
                        open_worktree(tree)
                        reload(tree.path)
            elif key == ord("d"):
                if rows:
                    tree = rows[selected]
                    if tree.main:
                        note = "the main worktree cannot be deleted"
                    else:
                        pending = tree
            elif key == ESC:
                if needle:
                    needle = ""
                else:
                    return
            elif key == ord("q"):
                return
    finally:
        curses.noraw()


def main() -> int:
    # ncurses waits a full second after a bare Esc for the rest of an escape
    # sequence; arrow keys arrive in one write, so a few milliseconds is plenty
    # and Esc stops feeling broken.
    os.environ.setdefault("ESCDELAY", "25")
    try:
        curses.wrapper(run)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
