#!/usr/bin/env python3
"""The CLI over linked tmux servers (tmux_link.py): what the pickers read, what
a peer is answered with, and how a link is made or removed.

  Get-TmuxLink.py --identity               this machine's user@hostname
  Get-TmuxLink.py --serve                  this machine's sessions and folders,
                                           as JSON: run over ssh by a peer
                                           (tmux_link.query), and by prefix+N to
                                           find out whether a host can be linked
  Get-TmuxLink.py --link <identity> <address>
  Get-TmuxLink.py --unlink <identity>      edit the peers file; run here and,
                                           over ssh, on the other machine
  Get-TmuxLink.py --format=peers           <identity> TAB <address> TAB <state> TAB <sessions>
  Get-TmuxLink.py --format=sessions        <host>:<session> TAB <shown name>, the
                                           linked machines' sessions (prefix+?
                                           without git-radar)
  Get-TmuxLink.py --format=folders         <host>/<folder> TAB <identity> TAB
                                           <address> TAB <path>, the first level
                                           of each linked machine's code folder
                                           (prefix+/)
  Get-TmuxLink.py --format=json            everything, this machine first

The formats read the snapshot Start-TmuxLink.py publishes; --live asks the peers
there and then instead.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tmux_link as link  # noqa: E402

# The muted grey a session on another machine has in the Git pane.
DIM = "\033[90m"
RESET = "\033[0m"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", action="store_true")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--link", nargs=2, metavar=("IDENTITY", "ADDRESS"))
    parser.add_argument("--unlink", metavar="IDENTITY")
    parser.add_argument("--format", choices=("peers", "sessions", "folders", "json"))
    parser.add_argument("--live", action="store_true",
                        help="ask the peers now instead of reading the snapshot")
    args = parser.parse_args()

    if args.identity:
        print(link.identity())
        return 0
    if args.serve:
        json.dump(link.serve(), sys.stdout)
        return 0
    if args.link:
        link.link(*args.link)
        return 0
    if args.unlink:
        link.unlink(args.unlink)
        return 0
    if not args.format:
        parser.error("nothing asked")

    machines = link.sample() if args.live else link.machines()
    peers = machines[1:]

    if args.format == "json":
        json.dump([link._encode(machine) for machine in machines], sys.stdout, indent=2)
        print()
    elif args.format == "peers":
        for machine in peers:
            print("\t".join([machine.identity, machine.address, machine.state,
                             str(len(machine.sessions))]))
    elif args.format == "sessions":
        for machine in peers:
            for session in machine.sessions:
                shown = session.get("label") or f"{machine.host}-{session['name']}"
                print(f"{link.session_key(machine.identity, session['name'])}\t{DIM}{shown}{RESET}")
    elif args.format == "folders":
        for machine in peers:
            for folder in machine.folders:
                print("\t".join([
                    f"{DIM}{machine.host}/{RESET}{folder}", machine.identity, machine.address,
                    os.path.join(machine.root, folder),
                ]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
