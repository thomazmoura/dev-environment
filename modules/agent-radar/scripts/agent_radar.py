"""Shared detection engine for agent-radar.

Answers one question about every tmux pane: is a coding agent running in it, and
is it waiting for me? Imported by Get-AgentState.py (the TSV producer) and by
Test-AgentRules.py (the rule-authoring explainer). Nothing here talks to fzf or
draws anything -- the consumers own presentation.

The design is lifted from the herdr architecture reference at the repo root; the
section numbers cited throughout refer to ai-cli-integration-architecture.md.
Three layers, deliberately independent so a failure in one degrades rather than
cascades:

  1. identification -- which agent is in this pane? (ps, not tmux)
  2. snapshot       -- what is on its screen? (tmux capture-pane)
  3. classification -- what does that screen mean? (rules/*.toml)

Identification picks the ruleset and nothing else; it never decides state.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

MODULE_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = MODULE_ROOT / "rules"

# The generic radar machinery lives with the other tmux helpers, because it is
# shared with git-radar and belongs to neither. Reached by relative path, the
# same way Select-Agent.sh reaches tmux-helpers.sh: the layout under modules/ is
# preserved by both deployments -- a ~/.modules symlink on the host, a COPY per
# module in Docker.
SHARED_SCRIPTS = MODULE_ROOT.parent / "tmux" / "scripts"
sys.path.insert(0, str(SHARED_SCRIPTS))

import radar_cache  # noqa: E402

# --- States ------------------------------------------------------------------
# Four, and resist adding a fifth (herdr S3.6). "Waiting for input" is BLOCKED;
# the difference between "waiting for approval" and "waiting for a prompt" is
# already carried by BLOCKED vs IDLE, and every consumer would have to learn a
# new value to gain nothing.
BLOCKED = "blocked"
WORKING = "working"
IDLE = "idle"
UNKNOWN = "unknown"

STATES = (BLOCKED, WORKING, IDLE, UNKNOWN)

# Presentation lives with the consumers, but the ordering is a detection fact:
# a blocked agent is the reason you opened the list, so it sorts first.
STATE_ORDER = {BLOCKED: 0, WORKING: 1, UNKNOWN: 2, IDLE: 3}

# --- Layer 1: identification -------------------------------------------------
# Executable basename -> canonical agent label. Reverse of herdr's agent table
# (S2.1). argv0 matching is a heuristic and not a fact: launcher shims, version
# stamped binaries and .cmd wrappers all break the naive form, so expect this
# table to grow an escape hatch per tool rather than staying tidy.
AGENT_ALIASES = {
    "claude": "claude",
    "claude-code": "claude",
    "codex": "codex",
    "copilot": "copilot",
    "github-copilot": "copilot",
    "ghcs": "copilot",
    "opencode": "opencode",
    "opencode2": "opencode",
    "open-code": "opencode",
}

# When the foreground process is one of these, its own name says nothing: the
# agent is whatever it was handed to run. Fall through to scanning argv.
RUNTIMES = {"node", "nodejs", "bun", "deno", "python", "python3", "pwsh", "bash", "sh"}

# Read out of the pane's own environment as a last resort, mirroring herdr's
# HERDR_AGENT hint (S2.2): sandbox and VM wrappers put a process between the
# shell and the agent, so the foreground job is the wrapper and no amount of
# argv scanning will find the agent underneath it.
AGENT_ENV_HINT = "AGENT_RADAR_AGENT"


@dataclass
class Process:
    pid: int
    ppid: int
    tty: str
    stat: str
    comm: str
    args: str

    @property
    def foreground(self) -> bool:
        # `+` in the stat field means the process is in the terminal's
        # foreground process group -- the only processes that can be what the
        # pane is currently showing.
        return "+" in self.stat


@dataclass
class Pane:
    pane_id: str
    session: str
    window: str
    label: str
    tty: str
    title: str
    current_command: str
    # The pane its session would show: active in its window, in the session's
    # current window. Not "focused" -- that needs a session to be focused *in*,
    # which is the consumer's half of the question. See list_panes.
    active: bool = False
    agent: str | None = None
    snapshot: str = ""
    state: str = UNKNOWN
    detail: str = ""
    rule_id: str = ""


def _run(argv: list[str]) -> str:
    """Run a command and return stdout, or "" if it fails.

    Every caller here is on the status-bar refresh path. A detector that raises
    because tmux was mid-restart would take the status bar down with it, so this
    fails open the way the herdr hook assets do (S4.4).
    """
    try:
        result = subprocess.run(
            argv, capture_output=True, text=True, check=False, timeout=5
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout


def list_panes() -> list[Pane]:
    """Every pane of every session, in one tmux call.

    @pane_label is set by modules/tmux/scripts/tmux-helpers.sh:label_pane for
    every pane the bindings open, which is why it beats the window name as a
    display label. It is a hint for identification, never the authority: panes
    started by hand do not have it.
    """
    fmt = "\t".join(
        [
            "#{pane_id}",
            "#{session_name}",
            "#{window_name}",
            "#{?@pane_label,#{@pane_label},#{window_name}}",
            "#{pane_tty}",
            "#{pane_title}",
            "#{pane_current_command}",
            # Two flags rather than one `#{&&:...}` expression: the combination
            # is a Python-side detail, and a format string that fails on an
            # older tmux would take the whole row with it.
            "#{pane_active}",
            "#{window_active}",
        ]
    )
    out = _run(["tmux", "list-panes", "-a", "-F", fmt])
    panes = []
    for line in out.splitlines():
        fields = line.split("\t")
        if len(fields) != 9:
            continue
        panes.append(
            Pane(*fields[:7], active=(fields[7] == "1" and fields[8] == "1"))
        )
    return panes


def current_session() -> str:
    """The session the caller is running in, or "" outside tmux.

    Resolved from $TMUX_PANE -- the pane this process was started in -- rather
    than from the attached client's session, so a client that has been switched
    elsewhere does not move the answer off the pane that asked.

    The consumer's half of "which agent am I focused on". `Pane.active` is the
    machine-wide half and is published with the snapshot; this cannot be,
    because the sampler is detached and belongs to no session. Each consumer
    asks once at startup -- a pane does not change session.

    The same function, for the same reasons, as git_radar.current_session. The
    two detectors are deliberately independent engines, so it is duplicated
    rather than shared.
    """
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return ""
    out = _run(["tmux", "display-message", "-p", "-t", pane, "#{session_name}"])
    return out.strip()


def list_processes() -> dict[str, list[Process]]:
    """Every process on the machine, grouped by tty, in one ps call.

    One call rather than one per pane: this runs on every status refresh, and
    the work is multiplicative over panes x clients (herdr S3.1 makes the same
    point about its screen reads).
    """
    out = _run(["ps", "-eo", "pid=,ppid=,tty=,stat=,comm=,args="])
    by_tty: dict[str, list[Process]] = {}
    for line in out.splitlines():
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue
        pid, ppid, tty, stat, comm, args = fields
        if tty in ("?", "-"):
            continue
        try:
            proc = Process(int(pid), int(ppid), tty, stat, comm, args)
        except ValueError:
            continue
        by_tty.setdefault(tty, []).append(proc)
    return by_tty


def _resolve_agent(proc: Process) -> str | None:
    """Map one process to an agent label, or None."""
    name = os.path.basename(proc.comm)
    if name in AGENT_ALIASES:
        return AGENT_ALIASES[name]
    if name not in RUNTIMES:
        return None
    # A runtime hosting the agent: `node /path/to/opencode`, or the pwsh wrapper
    # New-ToolPane.sh builds. Scan argv for the first token that names an agent.
    for token in proc.args.split():
        candidate = os.path.basename(token)
        if candidate in AGENT_ALIASES:
            return AGENT_ALIASES[candidate]
    return None


def _env_hint(pid: int) -> str | None:
    """Read AGENT_RADAR_AGENT out of a process's own environ.

    Note the direction: this reads the *target's* environment, so the hint
    applies only to that process and cannot leak globally the way an exported
    variable would (herdr S2.2).
    """
    try:
        raw = Path(f"/proc/{pid}/environ").read_bytes()
    except OSError:
        return None
    for entry in raw.split(b"\0"):
        key, _, value = entry.partition(b"=")
        if key.decode("utf-8", "replace") == AGENT_ENV_HINT:
            name = value.decode("utf-8", "replace").strip()
            return AGENT_ALIASES.get(name, name or None)
    return None


def identify(pane: Pane, by_tty: dict[str, list[Process]]) -> str | None:
    """Which agent is running in this pane, if any.

    #{pane_current_command} is not good enough here and the reason is structural:
    New-ToolPane.sh launches agents as `pwsh -Command claude`, so the pane's
    foreground process *group leader* is pwsh and that is the name tmux reports.
    This is herdr's "grandchild behind a shell" problem (S1.1) -- the agent has
    to be found by walking the tty's process list:

        pwsh    -Command claude      <- what tmux names
        claude                       <- what is actually running

    So: take the pane's tty, keep the foreground processes, and prefer the
    deepest one in the parent chain, because the agent is always further from
    the shell than its launcher is.
    """
    tty = pane.tty.removeprefix("/dev/")
    procs = by_tty.get(tty, [])
    foreground = [p for p in procs if p.foreground]

    by_pid = {p.pid: p for p in procs}

    def depth(proc: Process) -> int:
        steps, current = 0, proc
        seen = {current.pid}
        while current.ppid in by_pid and current.ppid not in seen:
            seen.add(current.ppid)
            current = by_pid[current.ppid]
            steps += 1
        return steps

    for proc in sorted(foreground, key=depth, reverse=True):
        agent = _resolve_agent(proc)
        if agent:
            return agent

    # The wrapped case: a sandbox or VM shim is the foreground job and the agent
    # is invisible to argv scanning. Ask the process itself.
    #
    # Only the deepest process, not every foreground one: the wrapper that hides
    # an agent is by definition the thing closest to it, and every extra
    # candidate is another /proc read on a path that runs for all panes on every
    # status refresh -- most of which hold a plain shell and will never match.
    if foreground:
        deepest = max(foreground, key=depth)
        hint = _env_hint(deepest.pid)
        if hint:
            return hint

    # Last resort, and the only path that works if /proc is unavailable.
    return AGENT_ALIASES.get(os.path.basename(pane.current_command))


# --- Layer 2: the snapshot ---------------------------------------------------

def capture(pane_id: str) -> str:
    """The exact text the rules are evaluated against.

    Deliberately not `capture-pane -J`: joining wrapped lines would change what
    the bottom-anchored regions see, and a status footer that wrapped would stop
    being its own line.

    capture-pane reads the pane's live screen, which is the property that makes
    the whole thing usable: scrolling back through an agent's history in
    copy-mode does not change what the detector sees (herdr S3.1 names this
    invariant and has a regression test for it).
    """
    return _run(["tmux", "capture-pane", "-p", "-t", pane_id]).rstrip("\n")


# --- Layer 2b: hook markers --------------------------------------------------
# The screen is the universal signal and stays the primary one. This is the
# narrow second channel for agents that will tell us directly: Claude Code runs
# hooks/Set-AgentRadarState.sh at the moments its state changes, and that script
# leaves a marker file per tmux pane.
#
# It only ever ADDS a blocked verdict, and only over idle. A pane the rules can
# see is working overrides its own marker (and clears it), so a marker orphaned
# by a crashed agent heals itself instead of pinning a row red forever -- the
# failure mode that would make the whole display stop being believed.


def cache_dir() -> Path:
    """Where the runtime state lives. agent_feed.cache_dir() delegates here.

    Defined in this module rather than in agent_feed because agent_feed imports
    this one, and detection cannot depend on the sampler -- the hook markers
    below live in the same directory as the published snapshot.
    """
    return radar_cache.cache_root("agent-radar")


def markers_dir() -> Path:
    return cache_dir() / "panes"


def _marker_path(pane_id: str) -> Path:
    # `%7` -> `7.json`; the hook drops the same `%` with ${TMUX_PANE#%}.
    return markers_dir() / f"{pane_id.lstrip('%')}.json"


def read_marker(pane_id: str) -> dict | None:
    """The pane's hook marker, or None. Never raises."""
    try:
        payload = json.loads(_marker_path(pane_id).read_text())
    except (OSError, ValueError):
        return None
    return payload if isinstance(payload, dict) else None


def clear_marker(pane_id: str) -> None:
    try:
        _marker_path(pane_id).unlink()
    except OSError:
        pass


def sweep_markers(live: set[str]) -> None:
    """Drop markers whose pane is gone.

    A pane can close while its agent is blocked -- that is in fact the normal
    way a blocked agent ends -- and nothing would ever run the clearing hook for
    it. Without this the directory grows forever and a recycled pane id
    inherits a stranger's marker.
    """
    if not live:
        # No panes at all means tmux failed to answer, not that every pane
        # closed -- _run() fails open and returns "". Sweeping on that would
        # delete a blocked agent's marker every time tmux hiccups.
        return
    try:
        entries = list(markers_dir().iterdir())
    except OSError:
        return
    for entry in entries:
        if entry.suffix != ".json":
            continue
        if f"%{entry.stem}" not in live:
            try:
                entry.unlink()
            except OSError:
                pass


# --- Regions -----------------------------------------------------------------
# Narrow the haystack before matching. Both a precision tool and a performance
# one: `bottom(3)` on a status footer cannot be fooled by a phrase scrolled by
# ten screens ago.

_REGION_RE = re.compile(r"^(bottom|top)\((\d+)\)$")

# A line that trims to a run of box-drawing horizontal rule, optionally followed
# by a label -- Claude Code draws its prompt box as two of these, the upper one
# labelled with the git branch:
#
#   ────────────────────────────────── agent-radar-replacement ─
#   > faca o push das duas branches
#   ────────────────────────────────────────────────────────────
_RULE_RE = re.compile(r"^\s*─{3,}(\s.*)?$")

# The INPUT cursor -- a bare `❯` with nothing numbered after it -- and the
# SELECTION cursor -- `❯ 1. Yes` -- which start with the same glyph and mean
# opposite things. Both live here rather than only in rules/claude.toml because
# the region below has to tell them apart to find the input box at all.
_PROMPT_CURSOR_RE = re.compile(r"^\s*❯(\s|$)")
_SELECTION_CURSOR_RE = re.compile(r"^\s*(│\s*)?❯\s+\d+\.\s")


def _input_box_open(lines: list[str]) -> int | None:
    """Index of the rule line that opens the agent's input box, or None.

    Found by what follows it, never by where it sits. The box is a rule line
    whose next non-empty line is the input cursor:

        ─────────────────────────────── agent-radar-replacement ─
        ❯ faca o push das duas branches
        ─────────────────────────────────────────────────────────

    Searched bottom-up so the live box wins over anything the transcript has
    scrolled past.
    """
    for index in range(len(lines) - 1, -1, -1):
        if not _RULE_RE.match(lines[index]):
            continue
        for line in lines[index + 1:]:
            if not line.strip():
                continue
            if _PROMPT_CURSOR_RE.match(line) and not _SELECTION_CURSOR_RE.match(line):
                return index
            break
    return None


def _above_prompt_box(snapshot: str) -> str:
    """Everything above the agent's input box.

    The defence against the agent's own UI being impersonated by its user. Every
    blocked-state phrase worth matching -- "do you want to proceed?", a numbered
    "❯ 1. Yes" selection cursor -- is something you could equally type into the
    prompt yourself, and a rule that cannot tell the difference will report you
    as blocked on your own draft message.

    Layout settles it where vocabulary cannot: an agent renders its dialogs
    above the input box, and anything below the box's opening rule is yours.
    Herdr solves the same problem with `whole_recent_without_current_prompt_marker`
    (S3.5); this is the box-drawing form of it.

    The box is located by its cursor, NOT by being the last pair of rule lines,
    and that distinction is the whole bug this function once had. Counting from
    the bottom assumes the input box owns the last two rules; it does not. Plan
    mode draws a banner box above it, and a dialog draws rules of its own, so on
    a real blocked screen `rules[-2]` landed *above the dialog* and cut the
    evidence out of the region -- every blocked rule then failed to match and the
    pane reported idle while it sat waiting for a keystroke. Do not reintroduce
    positional detection here; fixtures/claude-blocked-question-plan-mode.txt is
    that exact screen.

    Falls back to the whole snapshot when no input box is on screen. That is not
    a degraded case but the important one: Claude replaces the input box with the
    dialog while it is blocked, so a screen with no box has nothing of yours on
    it to exclude.
    """
    lines = snapshot.split("\n")
    open_index = _input_box_open(lines)
    if open_index is None:
        return snapshot
    return "\n".join(lines[:open_index])


class RuleError(ValueError):
    """A rule file is malformed. Raised at load, never at match time."""


def region_text(region: str, snapshot: str, title: str) -> str:
    if region == "title":
        # The OSC 0/2 title, handed over by tmux as #{pane_title}. This is the
        # closest thing to a structured signal an unmodified TUI offers: a short
        # string the agent sets deliberately, which does not move when the
        # layout reflows and survives a resize. Claude Code leads it with a
        # state glyph. Look for OSC evidence before writing screen rules.
        return title
    if region == "whole":
        return snapshot
    if region == "above_prompt_box":
        return _above_prompt_box(snapshot)

    match = _REGION_RE.match(region)
    if not match:
        raise RuleError(f"unknown region: {region!r}")
    kind, count = match.group(1), int(match.group(2))
    if count < 1:
        raise RuleError(f"region {region!r} needs a positive line count")

    lines = snapshot.split("\n")
    # Counted from *non-empty* lines, so the region is "the agent's status
    # footer" regardless of how much blank padding the layout inserted.
    filled = [index for index, line in enumerate(lines) if line.strip()]
    if not filled:
        return ""
    if kind == "bottom":
        start = filled[-count] if count <= len(filled) else filled[0]
        return "\n".join(lines[start:])
    end = filled[count - 1] if count <= len(filled) else filled[-1]
    return "\n".join(lines[: end + 1])


# --- Gates -------------------------------------------------------------------

@dataclass
class Gate:
    """A boolean test over a region's text.

    Semantics, copied from herdr S3.4 -- a gate matches iff ALL of:

      1. every string in `contains` is present (case-insensitive substring)
      2. every pattern in `regex` matches the region (use (?m)/(?s) as needed)
      3. every pattern in `line_regex` matches at least one line, case-SENSITIVE
      4. every nested gate in `all` matches
      5. if `any` is non-empty, at least one of its gates matches
      6. no gate in `not` matches

    The trap, and it catches everyone once: `contains` is AND. A list of strings
    looks like a list of alternatives and is not. OR is spelled
    `any = [{ contains = ["a"] }, { contains = ["b"] }]`.
    """

    contains: list[str] = field(default_factory=list)
    regex: list[re.Pattern] = field(default_factory=list)
    line_regex: list[re.Pattern] = field(default_factory=list)
    all: list["Gate"] = field(default_factory=list)
    any: list["Gate"] = field(default_factory=list)
    not_: list["Gate"] = field(default_factory=list)

    def matches(self, text: str, trace: list | None = None) -> bool:
        lowered = text.lower()
        for needle in self.contains:
            if needle not in lowered:
                _note(trace, f"contains {needle!r} not found")
                return False
        for pattern in self.regex:
            if not pattern.search(text):
                _note(trace, f"regex {pattern.pattern!r} did not match")
                return False
        if self.line_regex:
            lines = text.split("\n")
            for pattern in self.line_regex:
                if not any(pattern.search(line) for line in lines):
                    _note(trace, f"line_regex {pattern.pattern!r} matched no line")
                    return False
        for gate in self.all:
            if not gate.matches(text, trace):
                return False
        if self.any and not any(gate.matches(text) for gate in self.any):
            _note(trace, "no branch of `any` matched")
            return False
        for gate in self.not_:
            if gate.matches(text):
                _note(trace, "a `not` guard matched")
                return False
        return True

    @property
    def only_negative(self) -> bool:
        return bool(self.not_) and not (
            self.contains or self.regex or self.line_regex or self.all or self.any
        )


def _note(trace: list | None, message: str) -> None:
    if trace is not None:
        trace.append(message)


def _compile_gate(raw: dict, where: str) -> Gate:
    if not isinstance(raw, dict):
        raise RuleError(f"{where}: expected a table")
    known = {"contains", "regex", "line_regex", "all", "any", "not"}
    unknown = set(raw) - known
    if unknown:
        # Reject typos loudly. A silently ignored key is a rule that never fires
        # and a state that is quietly always wrong.
        raise RuleError(f"{where}: unknown key(s) {sorted(unknown)}")

    def patterns(key: str) -> list[re.Pattern]:
        out = []
        for item in raw.get(key, []):
            try:
                out.append(re.compile(item))
            except re.error as exc:
                raise RuleError(f"{where}: bad {key} {item!r}: {exc}") from exc
        return out

    def gates(key: str) -> list[Gate]:
        return [
            _compile_gate(item, f"{where}.{key}[{index}]")
            for index, item in enumerate(raw.get(key, []))
        ]

    gate = Gate(
        # Lower-cased once here so `matches` can compare against the lowered
        # region rather than re-casing every needle on every evaluation.
        contains=[str(item).lower() for item in raw.get("contains", [])],
        regex=patterns("regex"),
        line_regex=patterns("line_regex"),
        all=gates("all"),
        any=gates("any"),
        not_=gates("not"),
    )
    if gate.only_negative:
        # A purely negative gate matches an empty screen, which is never what an
        # author means (herdr S3.4).
        raise RuleError(f"{where}: a gate cannot consist only of `not`")
    return gate


@dataclass
class Rule:
    id: str
    state: str
    priority: int
    region: str
    detail: str
    gate: Gate


def load_rules(agent: str, rules_dir: Path | None = None) -> list[Rule]:
    """Load and compile one agent's rules, highest priority first.

    Ties go to the rule listed first in the file, so the file order is
    meaningful and a rule can be inserted above its neighbour without renumbering
    everything below it.
    """
    path = (rules_dir or RULES_DIR) / f"{agent}.toml"
    if not path.exists():
        return []
    with path.open("rb") as handle:
        document = tomllib.load(handle)

    rules = []
    for index, raw in enumerate(document.get("rules", [])):
        where = f"{path.name}[{index}]"
        raw = dict(raw)
        rule_id = raw.pop("id", None)
        if not rule_id:
            raise RuleError(f"{where}: every rule needs an id")
        state = raw.pop("state", UNKNOWN)
        if state not in STATES:
            raise RuleError(f"{where}: unknown state {state!r}")
        region = raw.pop("region", "whole")
        # Validate the region now rather than at match time, so a typo is a load
        # error you see immediately instead of a rule that silently never fires.
        region_text(region, "", "")
        rules.append(
            Rule(
                id=rule_id,
                state=state,
                priority=int(raw.pop("priority", 0)),
                region=region,
                detail=str(raw.pop("detail", "")),
                gate=_compile_gate(raw, where),
            )
        )
    rules.sort(key=lambda rule: -rule.priority)
    return rules


@dataclass
class Verdict:
    state: str
    detail: str
    rule_id: str


def classify(agent: str, snapshot: str, title: str, rules: list[Rule]) -> Verdict:
    """Evaluate an agent's rules against one screen.

    The fallback direction is the most important safety property here: a known
    agent whose screen matches nothing is IDLE, never a guessed BLOCKED (herdr
    S3.6). A false idle costs a stale row in a list. A false blocked sends you
    to a pane that did not need you, which is how a status display stops being
    believed.
    """
    for rule in rules:
        text = region_text(rule.region, snapshot, title)
        if rule.gate.matches(text):
            return Verdict(rule.state, rule.detail or rule.id, rule.id)
    return Verdict(IDLE, "", "default_idle_fallback")


def detect() -> list[Pane]:
    """The whole pipeline: every pane, identified, snapshotted and classified."""
    panes = list_panes()
    by_tty = list_processes()
    cache: dict[str, list[Rule]] = {}
    sweep_markers({pane.pane_id for pane in panes})

    found = []
    for pane in panes:
        agent = identify(pane, by_tty)
        if not agent:
            continue
        pane.agent = agent
        # Only agent panes are captured. Skipping the rest is most of the reason
        # this is cheap enough to run on the status-bar refresh path.
        pane.snapshot = capture(pane.pane_id)
        if agent not in cache:
            cache[agent] = load_rules(agent)
        verdict = classify(agent, pane.snapshot, pane.title, cache[agent])

        marker = read_marker(pane.pane_id)
        if marker is not None:
            if verdict.state == WORKING:
                # The screen wins, and proves the marker is stale: an agent that
                # is running a tool is not sitting on a dialog.
                clear_marker(pane.pane_id)
            elif verdict.state in (IDLE, UNKNOWN):
                # The case this channel exists for -- a dialog whose shape no
                # rule recognises. The agent told us itself.
                verdict = Verdict(
                    BLOCKED, str(marker.get("detail") or "waiting"), "hook_marker"
                )

        pane.state, pane.detail, pane.rule_id = (
            verdict.state,
            verdict.detail,
            verdict.rule_id,
        )
        found.append(pane)

    found.sort(key=lambda p: (STATE_ORDER.get(p.state, 9), p.session, p.pane_id))
    return found
