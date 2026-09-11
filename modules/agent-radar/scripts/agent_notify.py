#!/usr/bin/env python3
"""Tell you, away from tmux, that an agent wants you.

The radar already knows the two states that mean "your turn" -- BLOCKED (shown
as "waiting") and DONE -- and draws them in the status bar and the feeds. That
only helps while you are looking at tmux. This turns the moment a pane *enters*
one of them into an Event and hands it to every enabled Action: a Telegram
message, a desktop notification, whatever gets added next.

Only the sampler calls this (Start-AgentRadar.py), for the same reason the
debounce lives there: a transition is a fact about the *previous* sample, and it
is only correct while one process takes all the samples. Hooking it into
agent_feed.sample() instead would fire once per consumer that fell back to
sampling live.

  agent_notify.py --test               send a made-up "waiting" through every action
  agent_notify.py --test done --session notas

Adding an action: write a class with `name`, `enabled()` and `send(event)`, and
put an instance in ACTIONS. `enabled()` is asked once, when the sampler starts,
so an action whose configuration is missing simply sits out instead of failing
on every tick. AGENT_RADAR_NOTIFY=telegram,desktop narrows the set by name;
AGENT_RADAR_NOTIFY=off silences all of them.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agent_radar as radar  # noqa: E402

sys.path.insert(0, str(radar.SHARED_SCRIPTS))

import radar_cache  # noqa: E402

# The states worth interrupting you for. Exactly the two STATE_ORDER sorts above
# the rest, and for the same reason.
ATTENTION = {radar.BLOCKED: "waiting", radar.DONE: "done"}

# Screen reading can blink a blocked pane through one unknown frame and back.
# Each of those is an edge, and each edge would be a phone buzz. A second
# notification about the same pane in the same state inside this window is one
# you already have unread, so it is dropped.
REPEAT_AFTER = 30.0

# What the agent is called in a sentence. The radar's own ids are lowercase
# tokens meant for rules files, not for reading on a lock screen.
AGENT_NAME = {
    "claude": "Claude Code",
    "codex": "Codex",
    "copilot": "Copilot",
    "opencode": "opencode",
}

ENV_FILTER = "AGENT_RADAR_NOTIFY"


@dataclass
class Event:
    pane_id: str
    session: str
    window: str
    agent: str
    state: str
    detail: str = ""

    @classmethod
    def from_pane(cls, pane: radar.Pane) -> "Event":
        return cls(
            pane_id=pane.pane_id,
            session=pane.session,
            window=pane.window,
            agent=AGENT_NAME.get(pane.agent or "", pane.agent or "agent"),
            state=pane.state,
            detail=pane.detail,
        )

    @property
    def word(self) -> str:
        return ATTENTION.get(self.state, self.state)

    @property
    def title(self) -> str:
        return f"{self.session}: {self.agent} is {self.word}"

    @property
    def body(self) -> str:
        # A detail that only repeats the state word is noise, the same rule
        # Get-AgentState.extra_detail applies to the rows.
        return "" if self.detail in ("", self.word) else self.detail


# --- Actions -----------------------------------------------------------------


class TelegramAction:
    """What ~/.local/bin/send_notification.sh does, minus the shell quoting.

    The script builds its JSON by interpolating the message into a string, so a
    session name with a quote in it would break the payload. json.dumps cannot.
    """

    name = "telegram"
    TIMEOUT = 10.0

    def enabled(self) -> bool:
        return bool(os.environ.get("BOT_TOKEN") and os.environ.get("CHAT_ID"))

    def send(self, event: Event) -> None:
        text = event.title if not event.body else f"{event.title}\n{event.body}"
        request = urllib.request.Request(
            f"https://api.telegram.org/bot{os.environ['BOT_TOKEN']}/sendMessage",
            data=json.dumps({"chat_id": os.environ["CHAT_ID"], "text": text}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        # urlopen raises on a non-2xx status. Its message is the status line and
        # never the URL, so the token cannot end up in daemon.log.
        with urllib.request.urlopen(request, timeout=self.TIMEOUT) as response:
            reply = json.loads(response.read() or b"{}")
        if not reply.get("ok"):
            raise RuntimeError(f"telegram refused the message: {reply.get('description')}")


class DesktopAction:
    """A libnotify popup via notify-send.

    Waiting is sent critical because GNOME keeps critical notifications on
    screen until dismissed -- an agent blocked on you should not scroll away.
    Done is news, not an emergency, so it is allowed to time out.
    """

    name = "desktop"
    TIMEOUT = 5.0
    URGENCY = {radar.BLOCKED: "critical", radar.DONE: "normal"}
    ICON = {radar.BLOCKED: "dialog-question", radar.DONE: "emblem-default"}

    def enabled(self) -> bool:
        # No bus and no display means a headless sampler -- an ssh session, a
        # container -- where notify-send would fail on every event.
        has_session = any(
            os.environ.get(var)
            for var in ("DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "DISPLAY")
        )
        return has_session and shutil.which("notify-send") is not None

    def send(self, event: Event) -> None:
        argv = [
            "notify-send",
            "--app-name=agent-radar",
            f"--urgency={self.URGENCY.get(event.state, 'normal')}",
            f"--icon={self.ICON.get(event.state, 'dialog-information')}",
            event.title,
        ]
        if event.body:
            argv.append(event.body)
        subprocess.run(argv, check=True, capture_output=True, timeout=self.TIMEOUT)


# Every action there is. The one list to extend.
ACTIONS = [TelegramAction(), DesktopAction()]


def enabled_actions(actions: list | None = None) -> list:
    """The actions that are configured and not filtered out by AGENT_RADAR_NOTIFY."""
    wanted = os.environ.get(ENV_FILTER, "").strip().lower()
    if wanted in ("off", "none", "0"):
        return []
    names = {n.strip() for n in wanted.split(",") if n.strip()}
    return [
        action
        for action in (ACTIONS if actions is None else actions)
        if (not names or action.name in names) and action.enabled()
    ]


# --- Transitions -------------------------------------------------------------


def notify_path() -> Path:
    return radar.cache_dir() / "notify.json"


class Notifier:
    """Watches published states and fires on the way *into* ATTENTION.

    The previous states persist in notify.json rather than in memory, so a
    sampler that idle-exited and was respawned neither repeats what it already
    sent nor forgets what it had seen. With no file at all, the first sample is
    a baseline: agents already waiting when notifications were switched on are
    not announced in a burst.
    """

    def __init__(self, actions: list | None = None, path: Path | None = None) -> None:
        self.actions = enabled_actions(actions)
        self.path = path or notify_path()
        self._pool = (
            ThreadPoolExecutor(max_workers=len(self.actions), thread_name_prefix="notify")
            if self.actions
            else None
        )

    @property
    def active(self) -> bool:
        return bool(self.actions)

    def _load(self) -> dict | None:
        try:
            return json.loads(self.path.read_text())
        except (OSError, ValueError):
            return None

    def observe(self, panes: list[radar.Pane]) -> list[Event]:
        """Record this sample, dispatch its new attention states, return them."""
        if not self.active:
            return []

        previous = self._load()
        now = time.time()
        current, events = {}, []
        for pane in panes:
            entry = (previous or {}).get(pane.pane_id, {})
            sent_state, sent_at = entry.get("sent_state"), entry.get("sent_at", 0.0)

            entered = pane.state in ATTENTION and entry.get("state") != pane.state
            # The same "you watched it happen" test debounce uses to decide
            # between DONE and IDLE, so waiting and done are silenced alike.
            seen = pane.active and pane.attached
            repeat = sent_state == pane.state and now - sent_at < REPEAT_AFTER

            if previous is not None and entered and not seen and not repeat:
                events.append(Event.from_pane(pane))
                sent_state, sent_at = pane.state, now

            current[pane.pane_id] = {
                "state": pane.state,
                "sent_state": sent_state,
                "sent_at": sent_at,
            }

        # Panes that vanished drop out of the file, as in debounce.json.
        radar_cache.write_atomic(self.path, json.dumps(current))

        for event in events:
            self.dispatch(event)
        return events

    def dispatch(self, event: Event) -> None:
        """Every action gets the event on its own worker: a slow Telegram call
        cannot stretch the sampler's tick, and a failing one cannot stop the
        desktop popup."""
        for action in self.actions:
            self._pool.submit(_send, action, event)


def _send(action, event: Event) -> bool:
    try:
        action.send(event)
        return True
    except Exception as error:  # noqa: BLE001
        # stderr is daemon.log when the sampler runs detached.
        print(
            f"agent-radar: {action.name} notification failed for {event.pane_id}: {error!r}",
            file=sys.stderr,
            flush=True,
        )
        return False


# --- CLI ---------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--test",
        nargs="?",
        const="waiting",
        choices=sorted(ATTENTION.values()),
        help="send a made-up event through every enabled action",
    )
    parser.add_argument("--session", default="agent-radar-test")
    parser.add_argument("--agent", default="claude")
    parser.add_argument("--detail", default="")
    args = parser.parse_args()

    if not args.test:
        parser.print_help()
        return 0

    enabled = enabled_actions()
    for action in ACTIONS:
        print(f"{action.name:10} {'enabled' if action in enabled else 'skipped'}")

    state = next(s for s, word in ATTENTION.items() if word == args.test)
    event = Event(
        pane_id="%test",
        session=args.session,
        window="test",
        agent=AGENT_NAME.get(args.agent, args.agent),
        state=state,
        detail=args.detail or ("permission prompt" if state == radar.BLOCKED else ""),
    )
    # Synchronous, so the result can be reported before the process exits.
    ok = all([_send(action, event) for action in enabled])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
