#!/usr/bin/env python3
"""The theme colour each tmux session is drawn in. steward.nvim (:Steward themes)
is the screen that edits the settings file:

    ${XDG_CONFIG_HOME:-~/.config}/dev-environment/themes.json

    {
      "version": 1,
      "themes": [{ "name": "moon", "color": "#00abab" }, ...],
      "assignments": [
        { "match": "default", "theme": "moon" },
        { "match": "ApolloEnv@prod", "theme": "coral" }
      ]
    }

An assignment's match is one of these (steward's themes/parse.lua reads them the
same way):

    default            whatever nothing more specific matches (required)
    default (ssh)      an ssh session (prefix+N) no @Host key matches; default
                       (docker) the same for a Docker one (prefix+D). Blanks
                       around the name allowed, as steward writes it
    Directory          a local session whose directory is that folder or one under
                       it, the longest match winning. Path-like: it starts with / or
                       ~, or has a /. Relative to the code folder, as projects.json
    SessionName        a local session of that name, or of that prefix+$ label
                       (Set-SessionLabel.sh: dev-environment named ApolloEnv is
                       ApolloEnv). Anything not path-like
    Directory@Host     an ssh/Docker session (prefix+N, prefix+D) whose @ssh_dir is
                       that folder or one under it. Absolute. Split at the first @
    SessionName@Host   an ssh/Docker session of that name (@ssh_name, its
                       prefix+$ label, or the session's own name)

Host is the session's @ssh_target, whole (user@host, docker:name) or its host,
with or without the port it was opened with (user@host:port, host:port, host).

Most specific first: a local session takes SessionName, then Directory, then
default; an ssh/Docker session takes SessionName@Host, then Directory@Host, then
default (ssh) or default (docker) (a Docker session's target is docker:name),
then default. A session on a linked machine
(tmux_link) is drawn by that machine's tmux, from that machine's file.

Without the file nothing is printed and the theme is what it always was: @theme
for the bar (Set-Theme.sh), violet/Docker blue for ssh/Docker sessions. The
same goes for an ssh/Docker session in a file with no default at all.

    themes.py default
        the default theme's colour, or nothing
    themes.py session <name> <path> <ssh_target> <ssh_dir> <ssh_name> [<label>]
        the session's colour, or nothing (the empty ones for a local session;
        <label> is the session's @session_label, empty without one)
"""

from __future__ import annotations

import json
import os
import re
import sys

COLOUR = re.compile(r"^#?([0-9a-fA-F]{6})$")
CONNECTION = re.compile(r"^default\s*\(\s*(.*?)\s*\)$")


def settings_path() -> str:
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(config, "dev-environment", "themes.json")


def _colour(text) -> str | None:
    match = COLOUR.match(text.strip()) if isinstance(text, str) else None
    return f"#{match.group(1).lower()}" if match else None


def load(path: str | None = None) -> tuple[dict[str, str], list[tuple[str, str]]] | None:
    """({theme name: #rrggbb}, [(match, colour)]) from the file, assignments to
    themes that do not exist left out; None when there is no file, or it is
    broken (with a warning on stderr)."""
    path = path or settings_path()
    try:
        with open(path, encoding="utf-8") as file:
            data = json.load(file)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        print(f"themes: ignoring {path}: {error}", file=sys.stderr)
        return None
    if not isinstance(data, dict):
        print(f"themes: ignoring {path}: not a JSON object", file=sys.stderr)
        return None
    themes: dict[str, str] = {}
    for theme in data.get("themes") or []:
        if isinstance(theme, dict) and isinstance(theme.get("name"), str):
            colour = _colour(theme.get("color"))
            if colour:
                themes[theme["name"]] = colour
    assignments = []
    for assignment in data.get("assignments") or []:
        if not isinstance(assignment, dict):
            continue
        match, theme = assignment.get("match"), assignment.get("theme")
        if isinstance(match, str) and match.strip() and theme in themes:
            assignments.append((match.strip(), themes[theme]))
    return themes, assignments


def _path_like(text: str) -> bool:
    return text.startswith(("/", "~")) or "/" in text


def key_kind(key: str) -> tuple[str, str, str | None]:
    """(kind, subject, host): kind is default, connection (subject: ssh,
    docker, or another name nothing matches), directory, session,
    directory@host or session@host."""
    if key == "default":
        return "default", key, None
    connection = CONNECTION.match(key)
    if connection:
        return "connection", connection.group(1).lower(), None
    subject, at, host = key.partition("@")
    kind = "directory" if _path_like(subject) else "session"
    return (kind + "@host", subject, host) if at else (kind, subject, None)


def _depth_under(path: str, folder: str) -> int | None:
    """How long `folder` is when `path` is it or under it (for the longest match),
    else None."""
    folder = os.path.normpath(folder)
    if path == folder or path.startswith(folder.rstrip("/") + "/"):
        return len(folder)
    return None


def _bare_host(target: str) -> str:
    """The host alone: no ssh:// (a target given a port, ssh://user@host:port),
    no user and no :port -- as ssh_host in ssh-helpers.sh."""
    host = target.removeprefix("ssh://").rpartition("@")[2]
    match = re.match(r"^(\[[^]]+\]|[^:]+):[0-9]+$", host)
    return match.group(1) if match else host


def _host_matches(host: str, target: str) -> bool:
    return host in (target, target.removeprefix("ssh://"),
                    target.rpartition("@")[2], _bare_host(target))


def colour_for(assignments: list[tuple[str, str]], name: str, path: str = "",
               target: str = "", ssh_dir: str = "", ssh_name: str = "",
               label: str = "", root: str | None = None) -> str | None:
    """The colour of a session, or None when nothing in the file is for it (a
    file with no default, and for a remote session no key for it either)."""
    remote = bool(target)
    connection = ("docker" if target.startswith("docker:") else "ssh") if remote else None
    by_name = by_dir = by_connection = default = None
    deepest = -1
    for key, colour in assignments:
        kind, subject, host = key_kind(key)
        if kind == "default":
            default = default or colour
            continue
        if kind == "connection":
            if subject == connection:
                by_connection = by_connection or colour
            continue
        if remote != kind.endswith("@host"):
            continue
        if remote and not _host_matches(host, target):
            continue
        if kind.startswith("session"):
            if subject == name or (label and subject == label) \
                    or (remote and ssh_name and subject == ssh_name):
                by_name = by_name or colour
            continue
        if remote:
            if not subject.startswith("/"):
                continue
            here = os.path.normpath(ssh_dir) if ssh_dir else ""
            folder = subject
        else:
            if root is None:
                sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
                import tmux_link  # noqa: E402 -- only when a local folder is asked about
                root = tmux_link.code_folder()
            import project_folders  # noqa: E402
            here = os.path.realpath(path) if path else ""
            folder = os.path.realpath(project_folders.resolve(subject, root))
        depth = _depth_under(here, folder) if here else None
        if depth is not None and depth > deepest:
            deepest, by_dir = depth, colour
    return by_name or by_dir or by_connection or default


def main(argv: list[str]) -> int:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    if not argv or argv[0] not in ("default", "session"):
        print(__doc__, file=sys.stderr)
        return 2
    loaded = load()
    if loaded is None:
        return 0
    _, assignments = loaded
    if argv[0] == "default":
        colour = next((colour for key, colour in assignments if key == "default"), None)
    else:
        fields = (argv[1:] + [""] * 6)[:6]
        colour = colour_for(assignments, *fields)
    if colour:
        print(colour)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
