# agent-radar

Answers one question: **which coding agent is waiting for me right now?**

    prefix + t  then  a     popup picker -- pick an agent, jump to its pane
    prefix + t  then  A     the same list, live, in a normal pane
    prefix + t  then  r     the same live pane, chrome-free (curses, not fzf)
    status bar              ●2●1  -- two waiting, one working

The picker and the fzf watcher list one agent per line:

```
Autotrac_Starlink_Portal  Claude Code  claude  ● waiting  permission prompt
dev-environment           Claude Code  claude  ● working
herdr                     Claude Code  claude  ● idle     ready
```

The curses feed on `r` gives each agent two lines instead -- state and session
on top, what kind of agent it is and whatever it is waiting on underneath:

```
● waiting  Autotrac_Starlink_Portal
  Claude Code  permission prompt
● working  dev-environment
  Claude Code
● idle     herdr
  Claude Code  ready
```

One line per agent was the original shape, and in a 35%-wide pane it padded
every column to the width of the widest row, which turned the list into a block
of grey text. Two lines let each row be exactly as wide as it needs to be; when
the pane is narrower than a row, the session and the agent name are truncated
with an ellipsis before the detail is, because the detail is why you looked.

The state word stays padded -- the vocabulary is four fixed words, so that column
cannot grow to swallow the row, and keeping it aligned is what makes a `waiting`
row land where you last saw one.

[git-radar](../git-radar/README.md) has the same shape for the same reasons, and
both feeds draw with the primitives in
[`modules/tmux/scripts/radar_ui.py`](../tmux/scripts/radar_ui.py).

**The highlight follows the focus.** A feed is something you glance at from
another pane, so a selection band sitting there permanently is a cursor you
cannot move competing with the rows for attention. It appears when the pane has
the focus and disappears when it loses it, using the terminal's own focus
reporting (`CSI ?1004h`) which `focus-events on` in `modules/tmux/common.conf`
makes tmux forward. Polling tmux instead would have cost about 14ms per ask --
more per feed pane than sampling the whole machine does.

The second line is dim whether or not its row is selected. It is secondary by
definition, and brightening it on selection made the highlight shout twice.

## Why it is not demux

demux is a state *display*. It never discovers anything on its own -- every
agent has to push its state through that agent's own lifecycle hooks, which is
why `~/.claude/settings.json` grew fourteen `Set-DemuxAgentState.sh` entries and
why Codex, Copilot and OpenCode still report nothing at all.

agent-radar reads the agent's screen instead. The consequences:

- **No per-agent installation.** A tool it has never seen still gets identified
  and classified the moment someone writes rules for it.
- **It adopts agents you started by hand**, outside the tmux bindings.
- **It cannot go stale.** A hook cannot observe an Esc interrupt, a dismissed
  permission prompt or a crash, so a pushed state survives the thing it
  described. A screen read a second ago is a screen read a second ago.

The cost is that rules are hand-written and agent UIs change on their own
release cadence. Everything below exists to make that cheap.

There is now one optional hook, and it does not walk this back. demux's problem
is not that hooks exist, it is that a pushed state is the *only* state and
therefore outlives whatever it described. Here the screen is still the
authority: the marker a hook leaves can only ever add `blocked` to a pane the
rules see as idle, and a pane the rules see as working deletes it. A stale
marker survives exactly until the agent does anything. See
[The Claude Code hook](#the-claude-code-hook-optional-second-witness).

## How it works

Three layers, deliberately independent, adapted from the herdr design reference
at the repo root (`ai-cli-integration-architecture.md` -- section numbers in the
source comments point there).

| Layer | Question | Source |
| --- | --- | --- |
| identification | which agent is in this pane? | `ps`, **not** `#{pane_current_command}` |
| snapshot | what is on its screen? | `tmux capture-pane -p` |
| classification | what does that screen mean? | `rules/<agent>.toml` |

Identification picks the ruleset and nothing more; it never decides state.

A fourth, optional and agent-specific input sits beside these -- the hook marker
described below -- which can add `blocked` but never overrules what the screen
shows.

**Why not `#{pane_current_command}`.** The tmux bindings launch agents as
`pwsh -Command claude`, so the pane's foreground process *group leader* is pwsh
and that is the name tmux reports. The agent is a grandchild behind a shell:

```
pwsh -Command claude     <- what tmux names
  claude                 <- what is actually running
```

So the detector walks the tty's process list and prefers the deepest foreground
process, falling back to scanning argv for runtime-hosted agents (`node …`), then
to an `AGENT_RADAR_AGENT` hint read out of the process's own environ for
sandbox wrappers, then to tmux's answer.

**Why `capture-pane` is safe to read.** It returns the pane's live screen
regardless of copy-mode. Verified: with a pane scrolled 150 lines back,
`capture-pane -p` still returns the bottom. So you can page through an agent's
history without changing what it reports.

## One sampler, many readers

Every consumer used to detect for itself, which broke twice over as soon as you
left more than one open:

- **Cost multiplied by consumers, not by agents.** Detection is a `ps` plus a
  `capture-pane` per agent pane. A feed pane in each of five sessions, plus the
  status bar in each attached client, is that whole cost several times a second.
- **The debounce stopped working, silently.** The `working -> idle` smoothing
  compares each sample against the previous one through a shared cache file.
  Two pollers on different timers each read the *other's* sample as their own
  previous one, so the confirmation counter never accumulated -- and the only
  symptom was the flicker it was meant to remove.

So one process samples and everyone else reads what it publishes:

```
Start-AgentRadar.py ── detect + debounce, once a second ──> ~/.cache/agent-radar/
                                                              state.json
                                                              status.txt
                                        ┌──────────────────────────┘
      status bar ── Get-AgentSummary.sh ┤ cat status.txt
      prefix t a ── Select-Agent.sh     ┤ Get-AgentState.py --cached
      prefix t A ── Watch-Agents.sh     ┤
      prefix t r ── Watch-AgentFeed.py  ┘ agent_feed.sample_cached()
```

Nobody starts the sampler. The first consumer that finds the lock free spawns it
(`agent_feed.ensure_daemon`), and it exits on its own once tmux is gone or
nothing has read from it for 90 seconds -- so it never outlives what it watches.
The lock **is** the liveness check: the kernel releases it however the process
dies, which a pidfile cannot promise.

A reader that finds no snapshot, or one older than five seconds, samples live
instead and starts a sampler for next time. That fallback is what makes the
daemon an optimisation rather than a dependency: kill it mid-refresh and every
consumer keeps working, at the old cost, until it comes back.

Consequently the watchers refresh **once a second**, and opening one in every
session costs one file read per second each.

## The Claude Code hook (optional second witness)

Screen reading is the primary signal and needs no installation. For Claude Code
there is one optional extra, because it is the agent that will tell us directly:
`hooks/Set-AgentRadarState.sh` writes a marker file per tmux pane when Claude
raises a dialog, and removes it when the dialog is answered.

```
~/.cache/agent-radar/panes/7.json      <- pane %7 is blocked
```

It is strictly additive, and the precedence is what keeps it honest:

| Screen says | Marker says | Published |
| --- | --- | --- |
| blocked | anything | **blocked**, with the rule's own detail |
| working | blocked | **working** -- and the marker is deleted as stale |
| idle / unknown | blocked | **blocked**, `rule_id = hook_marker` |

So a marker orphaned by a crashed agent heals on the pane's next tool call
rather than pinning a row red forever, and a dialog whose shape no rule
recognises still turns the pane red. `detect()` also sweeps markers whose pane
no longer exists -- closing a pane while its agent is blocked is the normal way
a blocked agent ends, and nothing would ever run the clearing hook for it.

Verified live against Claude Code 2.1.263: a question dialog raises
`Notification` with `notification_type: permission_prompt`, and answering it
clears the marker through `PostToolUse` -- both without restarting the session.

**Which notification types count.** `permission_prompt`,
`worker_permission_prompt`, `agent_needs_input` and `elicitation_*` mean a
keystroke from you is the blocker. `idle_prompt` deliberately does **not**: it
fires when an agent has simply been sitting at a ready prompt for a while, and
mapping it to blocked would paint every idle pane red, destroying the one
distinction this tool exists to draw. An unrecognised type is ignored rather
than guessed, so a renamed type degrades to screen reading.

Install it with:

```bash
scripts/Install-AgentRadarHooks.sh              # idempotent; --uninstall reverses it
```

It backs `~/.claude/settings.json` up to `settings.json.bak-agent-radar`, only
touches entries whose command names `Set-AgentRadarState.sh`, and leaves other
tools' hooks on the same events alone -- Claude runs every hook registered for
an event, so demux and herdr keep working. To paste it by hand instead:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/.modules/agent-radar/hooks/Set-AgentRadarState.sh\" notification" } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/.modules/agent-radar/hooks/Set-AgentRadarState.sh\" clear" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/.modules/agent-radar/hooks/Set-AgentRadarState.sh\" clear" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/.modules/agent-radar/hooks/Set-AgentRadarState.sh\" clear" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/.modules/agent-radar/hooks/Set-AgentRadarState.sh\" clear" } ] }
    ]
  }
}
```

`clear` is spread over four events rather than trusting one, because a marker
that outlives its dialog is the failure users would never forgive. `PreToolUse`
is *not* among them: it fires **before** the permission prompt it would clear.

## The four states

`blocked` · `working` · `idle` · `unknown`. There is no fifth. "Waiting for
input" **is** `blocked` -- the difference between waiting for approval and
waiting for a prompt is already carried by `blocked` vs `idle`, and a fifth value
would have to be taught to every consumer to gain nothing.

An agent that is identified but whose screen matches no rule falls back to
`idle`, never to a guessed `blocked`. The direction is the point: a false idle
costs a stale row, a false blocked sends you to a pane that did not need you,
and a display that cries wolf stops being read.

## Writing rules

Rules are TOML, one file per agent, evaluated highest-priority-first with ties
going to the rule listed first. Read `rules/claude.toml` -- it documents the gate
grammar at the top.

The trap, once, so it only costs you once:

```toml
contains = ["a", "b"]                                     # AND -- both required
any = [{ contains = ["a"] }, { contains = ["b"] }]        # OR
```

Regions narrow the haystack before matching: `title` (the OSC title, which tmux
hands over as `#{pane_title}`), `whole`, `bottom(N)`, `top(N)` and
`above_prompt_box`. `N` counts non-empty lines, so `bottom(3)` is "the status
footer" regardless of blank padding.

`above_prompt_box` is the one worth understanding. Every phrase a blocked rule
wants to match -- "do you want to proceed?", a `❯ 1. Yes` selection cursor -- is
something you could equally type into the prompt yourself. Layout settles what
vocabulary cannot: agents render dialogs *above* the input box, so the box's
opening rule is the line that separates the agent's output from yours.
`fixtures/claude-idle-adversarial.txt` is that exact attack and still reads
`idle`.

Four authoring rules that pay for themselves:

1. **Gate on invariant controls, not prose.** Footer key hints (`esc to
   interrupt`, `enter to confirm`) describe the keyboard contract and do not
   churn; dialog titles change every release.
2. **Every `working` rule needs `not` guards against approval UI.** A permission
   dialog often renders over a still-visible working indicator. Without the
   guard the working rule wins on priority and the pane never reports blocked --
   the worst failure possible here, because you sit waiting for an agent that is
   waiting for you.
3. **Rank rules by evidence quality, not by state.** OSC title beats an anchored
   screen regex beats a generic phrase. Let priority encode trust.
4. **Add a narrow rule rather than widening a broad one.**

## The loop

Screen scraping fails silently: a rule that matched the wrong region and a rule
whose third `contains` failed look identical from the outside. So the tooling
comes first.

```sh
# 1. Put an agent into the state you care about, then capture it
scripts/Show-AgentSnapshot.sh %23 > fixtures/claude-blocked-bash-permission.txt

# 2. See exactly which rules fired, and why the others did not
scripts/Test-AgentRules.py --file fixtures/claude-blocked-bash-permission.txt --agent claude

# 3. Eyeball what a region actually contains
scripts/Test-AgentRules.py --pane %23 --region above_prompt_box

# 4. Edit rules/claude.toml, replay. No restart, no rebuild.

# 5. Check you did not break the cases that already worked
scripts/Test-Fixtures.sh
```

Fixtures are named `<agent>-<expected state>[-note].txt`, so the expectation
travels with the file and `Test-Fixtures.sh` needs no manifest.

## Files

| Path | |
| --- | --- |
| `scripts/agent_radar.py` | the engine: identification, regions, gates, classification |
| `scripts/agent_feed.py` | agent-specific backend: which fields get published, and the debounce |
| `../tmux/scripts/radar_cache.py` | shared with git-radar: publish, read, flock liveness, spawn-if-missing |
| `../tmux/scripts/radar_ui.py` | shared with git-radar: curses palette, banding, truncation |
| `scripts/Start-AgentRadar.py` | the one sampler; started by whichever consumer notices it is missing |
| `scripts/Get-AgentState.py` | CLI. `--format` = `tsv` \| `json` \| `fzf` \| `status`; `--cached` reads the shared snapshot |
| `scripts/Select-Agent.sh` | the popup picker (`prefix + t`, `a`) |
| `scripts/Watch-Agents.sh` | the live pane, fzf (`prefix + t`, `A`) |
| `scripts/Watch-AgentFeed.py` | the live pane, curses (`prefix + t`, `r`) |
| `scripts/Get-AgentSummary.sh` | the status-bar segment; a `cat` on the hot path |
| `scripts/Show-AgentSnapshot.sh` | what the matcher sees |
| `scripts/Test-AgentRules.py` | why each rule did or did not fire |
| `scripts/Test-Fixtures.sh` | regression check over `fixtures/` |
| `scripts/Install-AgentRadarHooks.sh` | registers the Claude hooks in `~/.claude/settings.json` |
| `hooks/Set-AgentRadarState.sh` | what Claude Code runs; writes/removes one marker per pane |
| `rules/*.toml` | one file per agent |

Two presentation formats live in `Get-AgentState.py` rather than in the shell
consumers, for one concrete reason: both pad columns around a multi-byte state
glyph, and `awk`'s `printf %-*s` counts bytes, so a shell formatter silently
under-pads every row. `Watch-AgentFeed.py` imports the same module, so the
vocabulary -- the state words, the glyph, the colours, and the rule that hides a
detail which only repeats the state word -- has exactly one definition.

## Known gaps

- Only `rules/claude.toml` has been validated against real screens. The codex,
  copilot and opencode files are transcribed from the herdr reference and need a
  pass with `Show-AgentSnapshot.sh` against live sessions.
- `blocked` fixtures exist only for Claude, and only for question dialogs
  (`claude-blocked-question`, and the same with plan mode's extra banner box --
  the pair that pins down the rule-line counting this once got wrong). A real
  tool-permission prompt and a plan approval are still uncaptured, because auto
  mode approves them before they render. With auto mode off:
  `Show-AgentSnapshot.sh %23 > fixtures/claude-blocked-permission.txt`.
- A pane that *prints* a dialog's text -- `cat` a fixture, or scroll a
  transcript that quotes one -- can read as blocked for as long as it is on
  screen. Inherent to screen reading; the input-box region only defends against
  text **you typed**, not against text an agent printed. The hook marker is
  unaffected.
- Claude Code's OSC title carries no state at the current version (it is the
  branch name behind a constant glyph), so all Claude signals come off the
  screen. Codex does set a stateful title, and its rules use it.
