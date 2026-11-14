#!/usr/bin/env python3
"""The project folders of this machine, one per line as <shown> TAB <path>: what
prefix+/ (New-CodeSession.sh) lists, and what prefix+N (New-SshSession.sh) runs
on a host with this dev-environment. The first level of the code folder plus
what ~/.config/dev-environment/projects.json adds (project_folders.py; edited
with steward.nvim's :Steward projects).

  Get-ProjectFolders.py           the folders, as above
  Get-ProjectFolders.py --all     every folder in the code folder, at any depth
                                  (fd), in the same format: prefix+/'s Ctrl-A
  Get-ProjectFolders.py --root    the code folder itself
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import project_folders  # noqa: E402
import tmux_link  # noqa: E402


def every_folder(root: str) -> int:
    fd = shutil.which("fd") or shutil.which("fdfind")
    if fd:
        command = [fd, "--type", "d", ".", "--base-directory", root]
    else:
        command = ["find", ".", "-mindepth", "1", "(", "-name", ".*", "-o", "-name", "node_modules",
                   "-o", "-name", "bin", "-o", "-name", "obj", ")", "-prune", "-o", "-type", "d", "-print"]
    process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE, text=True)
    for line in process.stdout:
        relative = line.rstrip("\n").removeprefix("./").rstrip("/")
        if relative:
            print(f"{relative}\t{os.path.join(root, relative)}")
    process.wait()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--root", action="store_true")
    args = parser.parse_args()

    root = tmux_link.code_folder()
    if args.root:
        print(root)
        return 0
    if args.all:
        return every_folder(root)
    for shown, path in project_folders.projects(root):
        print(f"{shown}\t{path}")
    return 0


if __name__ == "__main__":
    # fzf leaving, or reloading, while the tree is still listing closes the
    # pipe: end quietly, as fd would.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    raise SystemExit(main())
