"""The project folders the session pickers offer: what prefix+/ lists here, and
what a peer is told this machine has (tmux_link.serve, for prefix+/ there and
prefix+N on a linked host).

By default that is the first level of folders in the code folder. The settings
file adds more, and steward.nvim (:Steward projects) is the screen that edits it:

    ${XDG_CONFIG_HOME:-~/.config}/dev-environment/projects.json

    {
      "version": 1,
      "parents": ["clients", "~/work"],   folders whose children are listed
      "folders": ["~/notes", "/etc/nginx"] folders listed themselves
    }

A path is relative to the code folder (so one entry fits machines whose code
folders differ), ~/..., or absolute. The code folder is always a parent and is
never written to the file. Each machine reads its own file: a peer's folders
come from the peer's.

    settings_path()        where the file is
    load()                 (parents, folders) from it; empty when it is missing
    projects(root)         [(shown, path)] for the pickers, sorted

Hidden folders are left out, as are paths that do not exist; a folder reached
twice (a parent's child also listed on its own) is listed once.
"""

from __future__ import annotations

import json
import os
import sys

VERSION = 1


def settings_path() -> str:
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(config, "dev-environment", "projects.json")


def _paths(value) -> list[str]:
    if not isinstance(value, list):
        return []
    return [entry for entry in value if isinstance(entry, str) and entry.strip()]


def load(path: str | None = None) -> tuple[list[str], list[str]]:
    """The parents and the individual folders the file lists, as written. A
    missing file is no extra folders; a broken one is the same, with a warning
    on stderr -- the picker still opens on the code folder."""
    path = path or settings_path()
    try:
        with open(path, encoding="utf-8") as file:
            data = json.load(file)
    except FileNotFoundError:
        return [], []
    except (OSError, ValueError) as error:
        print(f"project_folders: ignoring {path}: {error}", file=sys.stderr)
        return [], []
    if not isinstance(data, dict):
        print(f"project_folders: ignoring {path}: not a JSON object", file=sys.stderr)
        return [], []
    return _paths(data.get("parents")), _paths(data.get("folders"))


def resolve(entry: str, root: str) -> str:
    """An entry as an absolute path: ~ expanded, relative ones under `root`."""
    path = os.path.expanduser(entry.strip())
    return os.path.normpath(os.path.join(root, path))


def shown(path: str, root: str) -> str:
    """How the picker shows a folder: relative to the code folder when it is in
    it (as prefix+/ always has), else ~/... under home, else absolute."""
    home = os.path.realpath(os.path.expanduser("~"))
    for base, prefix in ((root, ""), (home, "~/")):
        if path != base and path.startswith(base.rstrip("/") + "/"):
            return prefix + os.path.relpath(path, base)
    return "~" if path == home else path


def _is_dir(entry: os.DirEntry) -> bool:
    # A link to somewhere this user may not look (a /root/... one) raises
    # instead of answering: it is just not one of the folders.
    try:
        return entry.is_dir()
    except OSError:
        return False


def _children(parent: str) -> list[str]:
    try:
        with os.scandir(parent) as entries:
            return [entry.path for entry in entries
                    if not entry.name.startswith(".") and _is_dir(entry)]
    except OSError:
        return []


def projects(root: str, path: str | None = None) -> list[tuple[str, str]]:
    """The pickers' folders under the code folder `root` and the settings file:
    (shown, absolute path) pairs, sorted by what is shown."""
    root = os.path.realpath(root)
    parents, folders = load(path)
    candidates = _children(root)
    for parent in parents:
        candidates += _children(resolve(parent, root))
    candidates += [resolve(folder, root) for folder in folders]

    seen: set[str] = set()
    result = []
    for candidate in candidates:
        real = os.path.realpath(candidate)
        if real in seen or real == root or not os.path.isdir(real):
            continue
        seen.add(real)
        # The path as reached, not the real one: a folder linked into the code
        # folder shows where it was put.
        result.append((shown(os.path.normpath(candidate), root), os.path.normpath(candidate)))
    return sorted(result, key=lambda pair: pair[0].lower())
