# How Herdr Integrates With AI Coding CLIs

A design reference for anyone building a runtime that supervises interactive coding
agents. Written against the Herdr source tree; every claim cites the file it came
from so you can verify it and steal it.

Depth is concentrated on **GitHub Copilot CLI, Codex, Claude Code, and OpenCode**.
Other agents appear only where they illustrate a pattern those four don't.

---

## 1. The problem, and the shape of the answer

You want to run five coding agents at once and know, without looking at each one,
which is thinking, which is done, and which is stuck on a permission prompt.

None of these tools offer an API for that. Each is an interactive TUI: it takes the
terminal into raw mode, paints a full-screen interface, and repaints on every
keystroke. From the outside it is an opaque PTY that emits bytes. There is no
"status" call and no event stream.

Herdr's answer is **four independent layers**, deliberately decoupled so a failure in
one degrades rather than cascades:

| Layer | Question it answers | Authority |
| --- | --- | --- |
| 1. Process identification | *Which* agent is in this pane? | foreground process of the pane's tty |
| 2. State detection | *What* is it doing right now? | screen manifest **or** lifecycle hook — never both |
| 3. Session identity | *How do I bring this conversation back?* | hook-reported native session id |
| 4. Input | *How do I type into it safely?* | terminal-state-aware encoder |

The project states the decoupling as a hard rule in `CLAUDE.md`:

> **Detection is decoupled.** The detector reads a screen snapshot, never touches the
> parser or viewport state.

### 1.1 The framing fact: Herdr does not spawn agents

This shapes everything downstream, so state it first. Herdr never launches an agent
as a direct child process. It launches a **shell** in the pane, and then **types the
agent's command line into that shell's PTY**.

`start_agent()` in `src/app/agents.rs:195-216`:

```rust
let mut argv = vec![crate::detect::interactive_agent_executable(kind).to_string()];
argv.extend(params.args);
let command = crate::platform::interactive_shell_command(&argv, &shell_name)
    .ok_or(AgentStartError::InvalidArgument)?;
let bytes = crate::app::api_helpers::encode_api_submission(runtime, &command);
// ...
terminal.begin_managed_agent(name.clone(), kind, now, AGENT_START_SETTLE_DELAY, timeout);
if let Err(err) = runtime.try_send_bytes(Bytes::from(bytes)) { /* ... */ }
```

Session restore uses the identical mechanism (`src/app/agent_resume.rs:205-266`).

Four consequences that explain the rest of this document:

1. The agent is a **grandchild behind a shell**, so identification cannot use a known
   PID. It must go through the tty's foreground process group.
2. A launch requires the pane to already be at an **idle shell prompt**. There is no
   "create pane and run agent" atomic operation.
3. Users can start agents by hand, outside Herdr's knowledge. Detection must work for
   a process Herdr never launched — which is also what makes it work at all for
   agents started before Herdr was attached.
4. Everything Herdr knows afterward comes from either **the screen** or **a callback
   the agent itself makes**. There is no third channel.

If you are building an equivalent, you could instead spawn agents directly and keep
the PID. You would gain reliable identification and lose the ability to adopt an
agent a user started themselves. Herdr chose adoption.

---

## 2. Layer 1 — Process identification

**Purpose: pick the ruleset. Nothing more.** Process identity never determines state.

### 2.1 The agent table

`src/detect/mod.rs` holds a closed `Agent` enum (23 variants) and four tables over it:

- `agent_label(Agent) -> &'static str` — the canonical id used everywhere else:
  `claude`, `codex`, `copilot`, `opencode`, `agy` (Antigravity), `qodercli`, …
- `interactive_agent_executable(Agent) -> &'static str` — the binary Herdr types when
  launching. Usually equals the label, but not always: Cursor is `cursor-agent`
  (`cursor-agent.cmd` on Windows), Kiro is `kiro-cli`.
- `lookup_agent(name)` — the reverse map, from an observed process name.
- `Agent::SCREEN_MANIFEST_AGENTS` — the 21 agents that have a screen manifest.
  `Omp` and `Mastracode` are in `Agent::ALL` but absent here: they are hook-only.

`lookup_agent` (`src/detect/mod.rs:190-220`) matches on the **basename** and carries
an alias table, because the same tool appears under several names:

```rust
"claude" | "claude-code"                     => Some(Agent::Claude),
"codex"                                      => Some(Agent::Codex),
"copilot" | "github-copilot" | "ghcs"        => Some(Agent::GithubCopilot),
"opencode" | "opencode2" | "open-code"       => Some(Agent::OpenCode),
"cursor" | "cursor-agent"                    => Some(Agent::Cursor),
// ...
_ if is_muse_versioned_binary(name) => Some(Agent::Muse),
```

That last arm is worth dwelling on. Muse ships a launcher script that resolves the
active release and `exec`s `muse-bin-0.1.0-R708.1`, so the running process never
carries a bare `muse` name. The code comment explains the guard:

> Require a digit immediately after the `muse-bin-` prefix so unrelated binaries such
> as `muse-binary` or a bare `muse-bin` stay unmatched.

**Lesson:** argv0 matching is a heuristic, not a fact. Version-stamped binaries,
launcher shims, and `.cmd` wrappers all break the naive form. Budget for per-tool
escape hatches from day one.

### 2.2 When the process is hidden

Sandboxes and VM wrappers put a process between the shell and the agent, so the
foreground job is `fence` or `nono`, not `claude`. Herdr's escape hatch is an env
var read **out of the target process's own environment** — `parse_agent_env_hint` in
`src/platform/mod.rs:357` scans the environ block for `HERDR_AGENT=`:

```bash
HERDR_AGENT=claude fence -- claude
HERDR_AGENT=claude nono run --profile claude-code -- claude
```

Note the direction: Herdr reads the *child's* environ, so the hint only applies to
that foreground process and cannot leak globally the way an exported variable would.

A second hatch covers restricted Linux runtimes that expose no terminal foreground
process group at all: starting the server with `HERDR_PROCESS_DETECTION=child-groups`
opts into inferring the agent from direct child process groups. It is explicitly
best-effort — a newer background job can be mistaken for the foreground one — and the
default `native` mode never does it.

---

## 3. Layer 2a — Screen detection

This is the centerpiece, and the part most worth copying.

### 3.1 The snapshot: what the matcher actually sees

Path: `terminal.detection_text()` (`src/pane.rs:919`) → `src/terminal/runtime.rs:359`
→ `ghostty_detection_text` (`src/pane/terminal.rs:2666`) → `ghostty_recent_text`.

Four properties, each load-bearing:

**Bounded to one screen height.** The budget is the PTY's `rows()`, minimum 1, with
`DEFAULT_DETECTION_ROWS = 24` as fallback (`src/pane/terminal.rs:41`). Detection never
scans scrollback. An agent's live UI is always at the bottom; scanning history only
adds cost and false positives from old output.

**Anchored to the live bottom of the buffer, not the user's viewport.**
`ghostty_recent_read_range` (`src/pane/terminal.rs:2851`) computes, on the primary
screen, the viewport start, then walks *up* from the bottom to find the last non-blank
row, takes `end = max(last_content_row, cursor_row)` and
`start = end + 1 - lines`. On the alternate screen it is simply the last N rows of the
active area, since no scrollback exists there.

The consequence is the single most important usability property of the whole system:
**a user scrolling back through their agent's history does not change what the
detector sees.** There is a regression test named for exactly this —
`detection_text_stays_at_bottom_when_viewport_is_scrolled`
(`src/pane/terminal.rs:5282`).

**Plain text, never ANSI.** `ghostty_screen_row` (`src/pane/terminal.rs:2918`) renders
each row cell by cell: spacer-tail cells are skipped, empty cells and Kitty unicode
placeholders become a space, and each row is `trim_end`ed. Rows are joined with `\n`
after trailing blank rows are dropped. **No SGR byte ever reaches a matcher.**

This is a real design choice with a cost. You cannot write a rule like "matches when
the text is red," which for some agents would be a cleaner signal than the words. In
exchange, rules stay readable, cheap, and immune to theme changes. ANSI variants
(`recent_ansi`, `visible_ansi`) exist but serve `pane read --format ansi` only — and
notably, `ReadSource::Detection` returns `detection_text()` even when you ask for ansi
format (`src/app/api_helpers.rs:136-139`), because there is no ANSI form of the
detection snapshot to give you.

**Gated so it doesn't run.** `decide_detection_screen_read`
(`src/pane/agent_detection.rs:122`) skips reading the screen entirely when the state
is already Idle, the agent is known, nothing is pending or changed, and
`detection_content_seq` is unchanged since the last scan. `CLAUDE.md` names the reason:
this work is *multiplicative* — per event × panes × tabs × attached clients — so a
constant-cost early exit matters more than a fast matcher.

### 3.2 Out-of-band evidence: OSC sequences

Some agents already announce their state, just not through an API. They set the
terminal title. `AgentOscStateTracker` (`src/pane/osc.rs:459-527`) captures OSC 0/2
payloads as a `title` string and OSC 9 payloads as a `progress` string, strips control
characters, and caps the length.

These become **regions that bypass the screen entirely**:

```rust
match trimmed {
    "osc_title" => return input.osc_title,
    "osc_progress" => return input.osc_progress,
    _ => {}
}
```
(`src/detect/manifest.rs:1288-1293`)

An empty OSC 0 payload clears the title — the Codex pattern — and retained values are
wiped whenever the pane's foreground agent changes (`clear_retained`), so a stale title
from a previous agent cannot classify the current one.

This is why both `codex.toml` and `claude.toml` give their **highest-priority rules**
to `osc_title`. An OSC title is the closest thing to a structured signal an unmodified
TUI offers: it is a short string the agent sets deliberately, it does not move when
the layout reflows, and it survives a resize. If you are designing this system, look
for OSC evidence *before* writing screen rules.

### 3.3 The manifest schema

Manifests are TOML, one per agent, in `src/detect/manifests/`. The Rust types are
`AgentManifest` and `ManifestRule` in `src/detect/manifest.rs:138-198`, both
`#[serde(deny_unknown_fields)]` — a typo is a hard error, not a silently ignored key.

**Top-level:**

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | yes | must resolve to the agent |
| `version` | dotted numeric | optional bundled, **required remote** | each `.`-separated segment must be non-empty ASCII digits fitting in `u64` |
| `min_engine_version` | integer | optional bundled, **required remote** | rejected if `> MANIFEST_ENGINE_VERSION` (currently **3**) |
| `updated_at` | string | optional | parsed and **ignored** — documentation only |
| `aliases` | string array | optional | additional names that resolve to this agent |
| `rules` | array of tables | yes | 1 to 128 |

Agent matching (`manifest_matches_agent`, `manifest.rs:1141`) succeeds if `id` equals
the canonical label, or any alias does, or either parses to the agent. A mismatched
override is ignored with a warning rather than applied to the wrong tool.

**`[[rules]]`:**

| Field | Type | Default | Semantics |
| --- | --- | --- | --- |
| `id` | string | required | shown in `explain` output; name it after the screen it recognizes |
| `state` | `idle`\|`working`\|`blocked`\|`unknown` | `unknown` | published when this rule wins |
| `priority` | i32 | `0` | highest match wins; **ties go to the rule listed first** |
| `region` | string | `whole_recent` | see §3.5 |
| `visible_idle` / `visible_blocker` / `visible_working` | bool | false | only takes effect if `state` matches the flag |
| `skip_state_update` | bool | false | requires `state = "unknown"` and no `visible_*` |
| `contains` / `regex` / `line_regex` | string arrays | `[]` | matchers |
| `all` / `any` / `not` | gate arrays | `[]` | nested boolean structure |

The rule *is itself a gate*: `manifest_gate_from_rule` (`manifest.rs:1152`) copies its
six matcher fields into a `ManifestGate` and evaluates it.

### 3.4 Gate semantics — read this twice

From `compiled_gate_matches` (`manifest.rs:1237-1284`), a gate matches iff **all** of:

1. **every** string in `contains` is present — case-insensitive substring
2. **every** pattern in `regex` matches the region text (whole region, so use `(?m)` / `(?s)`)
3. **every** pattern in `line_regex` matches **at least one line** of the region — case-*sensitive*, so use `(?i)`
4. **every** nested gate in `all` matches
5. if `any` is non-empty, **at least one** of its gates matches (empty `any` is vacuously true)
6. **no** gate in `not` matches

> ⚠️ **`contains` is AND.** `contains = ["a", "b"]` requires both. This is the single
> most common authoring mistake, because a list of alternatives *looks* like a list of
> alternatives. The OR construct is `any = [{ contains = ["a"] }, { contains = ["b"] }]`.
> Everything defensive in `claude.toml` is built out of nested `any` and `not` for
> exactly this reason.

Regex is the Rust `regex` crate: no backreferences, no lookaround, but `\x{2733}`
unicode escapes work and are used heavily for spinner glyphs.

**Complexity caps** (`manifest.rs:266-271`):

```rust
const MAX_RULES_PER_MANIFEST: usize = 128;
const MAX_GATE_DEPTH: usize        = 8;
const MAX_TOTAL_GATES: usize       = 512;
const MAX_MATCHERS_PER_GATE: usize = 32;
const MAX_TOTAL_MATCHERS: usize    = 1024;
const MAX_MATCHER_CHARS: usize     = 512;
```

Caps exist because manifests are **remotely updatable** (§3.7). A fetched file is
untrusted input evaluated on a hot path; without bounds, a bad publish is a
denial-of-service on every pane. Validation also rejects any gate whose only content
is `not` — a purely negative gate matches an empty screen, which is never what an
author means.

### 3.5 Regions

Regions narrow the haystack before matching. This is both a precision tool and a
performance one.

**Whole-snapshot**
- `whole_recent` — everything (default)

**Prompt-marker-relative** — the "don't fire while the user is typing" family
- `after_last_prompt_marker` — text after the last `›` line
- `before_current_prompt_marker`
- `whole_recent_without_current_prompt_marker` — the whole snapshot, but **empty** if a
  current prompt marker exists
- `current_prompt_block_marker` / `after_current_prompt_block_marker` — relative to the
  last block marker (`•`, `■`, `✗`, `✓`) above the prompt

The third one is the clever one. Codex's `weak_blocker` rule looks for `[y/n]` and
`do you want to` — phrases a user could easily type into the prompt themselves.
Scoping it to `whole_recent_without_current_prompt_marker` makes the region collapse to
nothing while a prompt is active, so the rule structurally cannot fire on user input.

**Box- and rule-relative** — for agents that draw a framed input box
- `prompt_box_body` — between the second-from-bottom horizontal rule and the next rule
- `above_prompt_box`, `last_non_empty_above_prompt_box`
- `after_last_horizontal_rule`

A "horizontal rule" is a line that trims to leading `─` runs, matching if the remainder
is empty or the run is ≥3 characters (`is_horizontal_rule`, `manifest.rs:1511`) — so
`─── Some label` still counts as a rule.

**Counted**
- `bottom_lines(N)` — last N physical lines
- `bottom_non_empty_lines(N)` — from the Nth-from-last *non-blank* line to the end
- `top_non_empty_lines(N)` — start through the Nth non-blank line

`bottom_non_empty_lines` is the workhorse: it gives you "the agent's status footer"
regardless of how much blank padding the layout inserted. `top_non_empty_lines` is
gated on `min_engine_version >= 3` and parsed more strictly (no leading zero, ≤65535)
— a small demonstration of how a versioned DSL adds features without breaking old
clients.

**OSC** — `osc_title`, `osc_progress` (§3.2)

An unknown region at evaluation time yields `""` rather than panicking, but validation
rejects unknown names first, so a bad region is caught at load.

### 3.6 States, and the direction of failure

`AgentState` (`src/detect/mod.rs:11-20`) has exactly four values:

```rust
Idle, Working, Blocked, Unknown
```

**There is no "waiting for input" state — that is `Blocked`.** Resist adding a fifth;
every consumer (rollups, notifications, waits, the sidebar) would need to learn it, and
the distinction between "waiting for approval" and "waiting for a prompt" is already
carried by `Blocked` vs `Idle`.

The API layer adds one derived value from a *separate* fact
(`src/app/api_helpers.rs:96-107`):

```rust
(Idle,    false) => AgentStatus::Done      // idle, and you haven't looked at it
(Idle,    true)  => AgentStatus::Idle      // idle, and you have
(Working, _)     => Working
(Blocked, _)     => Blocked
(Unknown, _)     => Unknown
```

`done` is not a detection state. It is `idle` plus "unseen," so background work that
finished stays visible in the sidebar until you look at it. Keeping it out of the
detector means manifests never have to reason about focus.

**`skip_state_update`** is the escape hatch for screens that tell you nothing. When
Claude Code shows the transcript viewer or the model picker, the agent's real state is
whatever it was before — the overlay has hidden the evidence. Rather than guess, the
matching rule sets `skip_state_update` and the whole detection tick is *dropped*
(`detection_update_for_publish_with_osc` returns `None`,
`src/pane/agent_detection.rs:316`). Explain output records
`skipped_update_reason: "matched_rule:<id>"`.

**The fallback direction is the most important safety property in the system.** When
no rule matches for a *known* agent, the result is `Idle`, tagged
`default_known_agent_idle_fallback` (`manifest.rs:14`, `fallback_explain` at `:558`).
Never a guessed `Blocked`.

Why that direction: a false `idle` costs you a stale sidebar badge. A false `blocked`
would mean an automation waiting on `--until blocked` fires against an agent that is
actually mid-work. And combined with the refusal guard in §6.4 — `agent.prompt` returns
`agent_blocked` *before writing any bytes* — the strictness means a misclassification
can annoy you but can never cause Herdr to type into a dialog it misread. The docs
state the invariant plainly: it "should not make Herdr send input or take destructive
action."

**Publication policy** smooths the raw signal (`src/pane/agent_detection.rs:5-13`):

```rust
const AGENT_PENDING_IDLE_CONFIRMATIONS: u8 = 3;
const AGENT_PENDING_IDLE_CAP:  Duration = 700ms;   // hold working→idle this long
const AGENT_PENDING_IDLE_RECHECK: Duration = 100ms;
const STABLE_VISIBLE_SIGNAL_REFRESH: Duration = 800ms;  // re-publish steady blockers
const AGENT_STARTUP_GRACE_WINDOW: Duration = 3s;
```

A `Working` → plain-`Idle` transition is held for up to 3 confirmations or 700ms,
because agents blink through an idle-looking frame between tool calls. An idle carrying
`visible_idle`, or a `visible_blocker`, bypasses the hold — positive evidence needs no
confirmation. This is where a naive implementation produces a flickering sidebar; the
debounce belongs here, not in the UI.

### 3.7 Distribution and hot reload

Precedence, from `load_manifest_uncached` (`manifest.rs:599-696`):

1. **Local override** — `~/.config/herdr/agent-detection/<label>.toml`. Always wins if
   it parses, compiles, and matches the agent. Note the filename uses the *canonical
   label*: `copilot.toml` and `agy.toml`, not `github-copilot.toml`/`antigravity.toml`.
   Debug builds use a `herdr-dev` directory, so a dev override cannot poison the
   installed stable server.
2. **Cached remote** — `<state_dir>/agent-detection/remote/<label>.toml`, used only if
   its version is not older than bundled.
3. **Bundled** — `include_str!`-compiled into the binary. An invalid bundled manifest
   panics at load, which is correct: it is a build-time bug.

Failure at any tier degrades to the next with a warning surfaced in `explain`.

**Why remote patching exists at all:** agent UIs change on their own release cadence,
which is faster than yours. When Claude Code 2.1.228 swapped its busy spinner from
braille to half-circles, `claude.toml` needed one character class widened. Without
remote manifests that is a binary release; with them it is a file publish. The comment
recording that change is still in the manifest:

```toml
# Braille covers <= 2.1.227; half-circles are the 2.1.228 busy spinner.
regex = ['^[\x{2800}-\x{28FF}\x{25D0}-\x{25D3}] ']
```

Versioning rules (`process_agent_manifest`, `manifest_update.rs:314`) are strict:
newer version commits; **older** is an error; **equal version with different bytes** is
an error. That last rule is the interesting one — it makes a version number a real
identifier rather than a hint, so a cached manifest and a published one at the same
version are guaranteed identical. Commits are atomic (temp file → `write_all` +
`sync_all` → `rename` → parent dir fsync).

Catalog: `https://herdr.dev/agent-detection/index.toml`, fetched via `curl` with
retries, a 15s cap and a 256 KiB max filesize. Path entries are rejected if absolute,
empty, or containing `://` or `..`. The in-repo published copy is
`distribution/agent-detection/`, validated by
`scripts/agent_detection_manifest_check.py` — a standalone Python re-implementation of
the entire schema, so the publish gate does not depend on the Rust binary.

**The hard limit:** remote manifests can only patch *rules for agents the binary
already identifies*. A genuinely new agent needs Rust changes — an `Agent` variant,
`agent_label`, `lookup_agent`, `interactive_agent_executable`,
`SCREEN_MANIFEST_AGENTS`, `BUNDLED_MANIFESTS`. Splitting it this way is deliberate:
rules are data and churn constantly; identity is code and churns rarely.

### 3.8 Four manifests, annotated

#### GitHub Copilot CLI — the minimal viable shape

`src/detect/manifests/github-copilot.toml` (45 lines, 3 rules):

```toml
id = "copilot"
version = "2026.08.29.1"
min_engine_version = 1
aliases = ["github-copilot", "ghcs"]

[[rules]]
id = "selection_blocker"
state = "blocked"
priority = 300
region = "whole_recent"
visible_blocker = true
all = [
  { any = [
    { contains = ["esc to cancel"] },
    { contains = ["esc cancel"] },
  ] },
  { any = [
    { contains = ["enter to select"] },
    { contains = ["enter to confirm"] },
    { contains = ["enter to submit"] },
    { contains = ["enter accept"] },
  ] },
]

[[rules]]
id = "background_agents_working"
state = "working"
priority = 110
region = "bottom_non_empty_lines(6)"
visible_working = true
line_regex = ['^\s*◎\s+Waiting for background agents(?:\s|·|$)']

[[rules]]
id = "working_cancel_hint"
state = "working"
priority = 100
region = "whole_recent"
visible_working = true
any = [
  { contains = ["esc to cancel"] },
  { contains = ["esc cancel"] },
  { contains = ["esc again to cancel"] },
  { contains = ["esc interrupt"] }
]
```

This is the template to start from for a new tool. Two observations:

**The AND-of-ORs shape.** `selection_blocker` requires *a cancel hint* AND *a
selection hint*, each expressed as an OR over spelling variants. Neither alone is
enough: "esc to cancel" appears while the agent is merely working (that is
`working_cancel_hint`, priority 100). It is the *combination* that means a dialog is
open. Priority 300 vs 100 resolves the overlap — both rules match a blocked screen,
and the blocker wins.

**Gate on controls, not prose.** Every matcher here targets a **footer key hint** —
the "esc to cancel / enter to select" affordance line. Those strings are invariant
because they describe the keyboard contract; the dialog's *title* changes with every
feature. This is the single most transferable authoring rule in the whole system.

#### Codex — OSC first, screen as fallback

`src/detect/manifests/codex.toml` (89 lines, 7 rules), abridged to the structure:

```toml
id = "codex"
min_engine_version = 3

[[rules]]                      # priority 1100
id = "osc_title_blocked"
state = "blocked"
region = "osc_title"
contains = ["Action Required"]

[[rules]]                      # priority 1050
id = "osc_title_working"
state = "working"
region = "osc_title"
regex = ['(?:^| )[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏](?: |$)']

[[rules]]                      # priority 1000 — skip_state_update
id = "transcript_viewer"
state = "unknown"
region = "after_last_prompt_marker"
skip_state_update = true
contains = ["↑/↓ to scroll", "pgup/pgdn to", "home/end to jump", "q to quit"]
any = [
  { contains = ["esc to edit prev"] },
  { contains = ["esc/← to edit prev"] },
]

[[rules]]                      # priority 950
id = "trust_directory"
state = "blocked"
region = "top_non_empty_lines(20)"
all = [
  { regex = ['\A> You are in [^\r\n]+(?:\r?\n|$)'] },
  { regex = ['(?s)Do\s+you\s+trust\s+the\s+contents\s+of\s+this\s+directory\?'] },
]

[[rules]]                      # priority 600
id = "weak_blocker"
state = "blocked"
region = "whole_recent_without_current_prompt_marker"
any = [
  { contains = ["[y/n]"] },
  { contains = ["yes (y)"] },
  { contains = ["do you want to"], any = [{ contains = ["yes"] }, { contains = ["❯"] }] },
  { contains = ["would you like to"], any = [{ contains = ["yes"] }, { contains = ["❯"] }] },
]

[[rules]]                      # priority 500
id = "screen_working_fallback"
state = "working"
region = "bottom_non_empty_lines(3)"
line_regex = ['^[•◦]\s+Working \([^)]*esc to interrupt\)(?: · .*)?$']
not = [{ contains = ["■ Conversation interrupted"] }]
```

Codex is the best illustration of **layered evidence quality**. The priority ladder
literally ranks how much each signal is trusted:

- **1100/1050** — OSC title. Codex sets `Action Required` and a braille spinner in the
  terminal title. This is deliberate signalling by the tool; trust it most.
- **950** — `trust_directory`, the first-run dialog, matched in `top_non_empty_lines(20)`
  because it renders at the *top* of a fresh screen. It needs both the `> You are in …`
  header anchored to the start (`\A`) and the question, so a chat message quoting the
  phrase cannot trigger it.
- **600** — `weak_blocker`, named for what it is: generic yes/no phrasing that could
  come from anywhere. Neutralized during typing by
  `whole_recent_without_current_prompt_marker`.
- **500** — `screen_working_fallback`, a fully line-anchored regex on the exact status
  line, in the bottom 3 non-empty lines, with a `not` guard against the "Conversation
  interrupted" frame that still contains the phrase.

The 1000-priority `transcript_viewer` sits *above* everything except the OSC rules
because when the transcript overlay is open, the screen genuinely no longer carries
evidence — better to hold the previous state than to read the overlay's text.

#### Claude Code — the mature, defensive one

`src/detect/manifests/claude.toml` (218 lines, 17 rules) is what a manifest looks like
after a long tail of bug reports. Rather than reprint it, here is what it teaches.

**Character classes with version comments**, because spinner glyphs change between
releases:

```toml
regex = ['^[\x{2800}-\x{28FF}\x{25D0}-\x{25D3}] ']
```
and the repeated `[\x{002A}\x{00B7}\x{2722}\x{2736}\x{273B}\x{273D}]` — `*`, `·`, and
four sparkle variants — across the working rules. Widening a class is a smaller,
safer edit than adding a rule.

**Column-zero anchoring to defeat impersonation.** From `background_mcp_task_working`:

```toml
# Claude renders activity summaries at column zero; wrapped continuations are indented.
# Keeping that shape prevents user prompt text from impersonating this signal.
regex = ['(?m)^[\x{002A}\x{00B7}…][ \t]+\S[^\n]*?(?:\n[ \t]+[^\n]*?){0,3}·…']
```

The threat model is explicit: a user could type the same words into the prompt box.
The defense is *layout*, not vocabulary — agent-rendered summaries start at column
zero and indent their wraps; pasted text does not have that shape.

**`not` guards on working rules.** The same rule carries:

```toml
not = [
  { contains = ["do you want to proceed?"] },
  { contains = ["esc to cancel"] },
  { contains = ["waiting for permission"] },
  { contains = ["do you want to allow this connection?"] },
  { contains = ["tab to amend"] },
  { contains = ["ctrl+e to explain"] },
]
```

Generalize this: **every working rule needs `not` guards against approval UI.** A
permission dialog often renders *over* a still-visible working indicator. Without the
guard the higher-priority working rule wins and the pane silently never reports
blocked — the worst failure this system can produce, because you sit waiting for an
agent that is waiting for you.

**A rule per real bug.** `mcp_elicitation_prompt` carries its own postmortem:

```toml
# MCP elicitation dialogs (elicitation/create) show Accept/Decline controls
# with an "Esc to cancel" footer but no Enter hint, so live_blocked_form
# cannot see them (issue #3283). Gate on the invariant header line, the
# Accept/Decline control line, and the cancel footer.
```

The general blocked rule assumed every dialog has an Enter hint. One did not. Rather
than loosen the general rule — which would have cost precision everywhere — a narrow
rule was added at the same priority. **Prefer a new narrow rule over widening a broad
one.**

**Precise idle.** `live_prompt_box` matches `^\s*❯` in `prompt_box_body` only, with a
`not` list of every navigation hint, so a *selection* cursor in a menu is never
mistaken for an *input* cursor at a ready prompt.

#### OpenCode — the counterpoint

`src/detect/manifests/opencode.toml` is 37 lines and 3 rules: one blocked, two
working. It is thin *on purpose*, because OpenCode ships a real plugin (§4.4) that is
the lifecycle authority whenever installed. The manifest only has to cover the
un-plugged case.

Its blocked rule shows the deepest gate nesting in the bundled set (rewrapped here;
it is one long line in the source):

```toml
any = [
  { contains = ["△ Permission required"] },
  { contains = ["esc dismiss"],
    any = [ { contains = ["enter confirm"] }, { contains = ["enter submit"] },
            { contains = ["enter toggle"] } ],
    all = [ { any = [ { contains = ["↑↓ select"] }, { contains = ["⇆ tab"] } ] } ] },
]
```

Read it as: *either* the explicit permission banner, *or* (a dismiss hint AND one of
three confirm hints AND one of two navigation hints). The first branch is the cheap
precise signal; the second is the structural fallback for dialogs that lack the banner.

**The lesson from the pair:** manifest complexity is inversely proportional to
integration quality. Claude Code needs 17 rules because screen scraping is the only
channel. OpenCode needs 3 because it can just be asked.

### 3.9 Transferable authoring rules

1. **Gate on invariant controls, not prose.** Footer key hints are the contract; titles
   and messages are decoration.
2. **Prefer `line_regex` with anchors over bare `contains`.** `^\s*❯` cannot appear
   mid-sentence; `❯` can.
3. **Every working rule needs `not` guards against approval UI.** See §3.8.
4. **Use the narrowest region that still contains the evidence.** `bottom_non_empty_lines(3)`
   over `whole_recent` whenever the signal is a status footer.
5. **Rank rules by evidence quality, not by state.** OSC > anchored screen regex >
   generic phrase. Let priority encode trust.
6. **Add a narrow rule rather than widening a broad one.**
7. **Comment the failure each rule defends against.** Every non-obvious rule in
   `claude.toml` does, and that is why it is still maintainable at 17 rules.

---

## 4. Layer 2b — Lifecycle hooks

Screen scraping is a fallback. When a tool exposes hooks, ask it directly.

### 4.1 The environment contract

Every process launched in a pane gets a fixed set of variables. From
`apply_pane_launch_env` (`src/pane.rs:138-160`):

```rust
fn apply_pane_launch_env(cmd: &mut CommandBuilder, launch_env: &PaneLaunchEnv) {
    cmd.env_remove("CODEX_THREAD_ID");
    for (key, value) in &launch_env.extra { cmd.env(key, value); }
    cmd.env(crate::HERDR_ENV_VAR, crate::HERDR_ENV_VALUE);   // HERDR_ENV=1
    crate::integration::apply_pane_base_env(cmd);            // HERDR_SOCKET_PATH, HERDR_BIN_PATH
    crate::platform::apply_pane_runtime_marker(cmd);
    match &launch_env.identity {
        PaneLaunchIdentity::Inherit => {}
        PaneLaunchIdentity::Managed { workspace_id, tab_id, pane_id } => {
            cmd.env(HERDR_WORKSPACE_ID_ENV_VAR, workspace_id);
            cmd.env(HERDR_TAB_ID_ENV_VAR, tab_id);
            cmd.env(HERDR_PANE_ID_ENV_VAR, pane_id);
        }
        PaneLaunchIdentity::OmitPane => { cmd.env_remove(HERDR_PANE_ID_ENV_VAR); }
    }
}
```

| Variable | Purpose |
| --- | --- |
| `HERDR_ENV=1` | the "am I inside?" guard; every hook checks this first |
| `HERDR_SOCKET_PATH` | where to send JSON |
| `HERDR_BIN_PATH` | absolute path to the herdr binary (`current_exe()`) |
| `HERDR_PANE_ID` | **which pane to report about** — the addressing key |
| `HERDR_WORKSPACE_ID` / `HERDR_TAB_ID` | context |

Three details worth copying:

**`HERDR_ENV=1` as a universal no-op guard.** Every hook exits 0 immediately without
it. This is what makes it safe to install a hook globally in a user's `~/.claude`: it
does nothing outside Herdr, so the user's normal terminal sessions are unaffected.

**`env_remove("CODEX_THREAD_ID")`** — one line, real bug prevented. Codex exports its
thread id; without the scrub, a new pane launched from inside a Codex session inherits
it and the hook reports the *parent's* conversation for the child pane.

**`PaneLaunchIdentity::OmitPane`** actively *removes* `HERDR_PANE_ID` rather than
leaving it unset, so a nested process cannot inherit a stale pane address. Absence must
be explicit when the variable might already be in the environment.

### 4.2 The reporting API

Two transports carry identical payloads.

**Socket** — a newline-delimited JSON request to `HERDR_SOCKET_PATH`. Unix domain
socket, or a named pipe on Windows (`src/ipc.rs:35-52`); the JS assets translate:

```js
const socketEndpoint =
  process.platform === "win32" ? `\\\\.\\pipe\\${socketPath}` : socketPath;
```

**CLI** — `$HERDR_BIN_PATH pane <verb>` (`src/cli/spec.rs:645-694`):

```bash
"$HERDR_BIN_PATH" pane report-agent "$HERDR_PANE_ID" \
  --source custom:my-agent --agent my-agent --state working [--message T] [--seq N] \
  [--agent-session-id ID] [--agent-session-path PATH]

"$HERDR_BIN_PATH" pane report-agent-session "$HERDR_PANE_ID" --source … --agent … --agent-session-id …
"$HERDR_BIN_PATH" pane release-agent       "$HERDR_PANE_ID" --source … --agent …
"$HERDR_BIN_PATH" pane report-metadata     "$HERDR_PANE_ID" --source … [--title T] [--token K=V] …
```

RPC methods: `pane.report_agent`, `pane.report_agent_session`, `pane.release_agent`,
`pane.report_metadata` (`src/api/schema.rs:219`).

Design points:

- **`--source` namespacing.** `herdr:<agent>` is reserved for Herdr's own bundled
  integrations; third parties use `custom:<name>`. §5.2 shows this is a real privilege
  boundary, not a naming convention.
- **`--seq` for ordering.** Every asset passes `time.time_ns()`. Hooks fire from
  concurrent processes over a datagram-ish path; stale sequence numbers from the same
  source are ignored. Without this a fast `working` → `idle` pair can land reversed and
  leave the pane permanently "working."
- **`release-agent` on exit.** Authority is a claim that must be given back, or a dead
  hook's last report sticks forever.
- **Semantics vs presentation are split.** `report-metadata` carries `--title`,
  `--display-agent`, `--state-label`, and `--token` — all **visual only**. Waits,
  notifications, and rollups use the semantic state exclusively. This lets a user's own
  hook decorate a pane without accidentally taking over its lifecycle authority.

### 4.3 The one-authority rule

The most important structural decision in this layer:

> When a full-lifecycle integration is installed and actively reporting for a pane,
> Herdr does **not** also run screen manifest detection for that pane.

Exposed as `screen_detection_skipped: true` with
`screen_detection_skip_reason: "full_lifecycle_hook_authority"`
(`src/app/api/agents.rs:238-262`). The eligible set is a hardcoded list
(`src/detect/mod.rs:316`):

```rust
("herdr:pi","pi") | ("herdr:omp","omp") | ("herdr:mastracode","mastracode")
| ("herdr:opencode","opencode") | ("herdr:kilo","kilo") | ("herdr:kimi","kimi")
```

Six agents. Everyone else — **including Claude Code, Codex, and Copilot** — keeps
screen detection as the state authority even with their hook installed.

That seems backwards until you see the reasoning. Those three hooks only fire on
`SessionStart`. They cannot observe an escape-key interrupt, a cancelled permission
prompt, or a crash. A *partial* lifecycle integration is **worse than none**: it
reports `working`, then goes quiet, and the pane is wrong indefinitely with no
fallback — because the fallback was disabled by the presence of the "integration."

So the rule is not "hooks beat screen." It is **one authority per pane, and a hook only
earns it by covering the whole lifecycle.** Everything else is downgraded to
session-identity-only, a role it can fill perfectly.

Herdr enforces this at the boundary rather than by convention:
`is_reserved_native_state_source()` (`src/agent_resume.rs`) lists claude, codex,
copilot, devin, droid, qodercli, qwen, cursor, grok as sources **forbidden from claiming
lifecycle state at all**. A bug in the Claude hook cannot take over state; the server
rejects it.

### 4.4 Two hook shapes, walked through

#### Shell hook — `src/integration/assets/copilot/herdr-agent-state.sh`

The pattern used by claude, codex, copilot, devin, droid, kimi, cursor, grok,
qodercli, qwen, antigravity, mastracode:

```sh
#!/bin/sh
# installed by herdr
# managed by herdr; reinstalling or updating the integration overwrites this file.
# add custom hooks beside this file instead of editing it.
# HERDR_INTEGRATION_ID=copilot
# HERDR_INTEGRATION_VERSION=3

set -eu

hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-copilot-hook.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

[ "${HERDR_ENV:-}" = "1" ]        || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ]   || exit 0
[ -n "${HERDR_PANE_ID:-}" ]       || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
# ... parse JSON, filter events, build request ...
try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    client.connect(socket_path)
    client.sendall((json.dumps(request) + "\n").encode("utf-8"))
    try: client.recv(4096)
    except Exception: pass
    client.close()
except Exception:
    pass
PY
```

Eight things this file does right:

1. **A self-describing banner** with `HERDR_INTEGRATION_ID` and
   `HERDR_INTEGRATION_VERSION`, plus a plain-English instruction to add custom hooks
   *beside* the file rather than editing it. This is a file living in the user's home
   directory; it has to explain itself.
2. **stdin captured to a temp file first**, with a `trap` covering `EXIT HUP INT TERM`.
   The payload arrives on stdin and can only be read once.
3. **Guards before any work.** Missing `HERDR_ENV` means exit 0 — success, no output.
4. **`|| exit 0` on `mktemp`**, so even the setup step fails open.
5. **Every network operation wrapped in `try/except: pass`.** A hook that fails must
   never break the agent it is hooked into. **This is the single most important
   property**: you are running inside someone else's process on their critical path.
6. **A 500ms socket timeout.** A hung Herdr must not hang the agent.
7. **`client.recv(4096)` then discard.** Reads the ack so the server can close cleanly,
   ignores the content.
8. **`python3` for JSON**, because POSIX sh cannot parse JSON safely. Note the real
   cost: no `python3`, silent no-op. A PowerShell twin (`.ps1`) exists for Windows,
   using the CLI wrapper instead of raw sockets.

#### Plugin — `src/integration/assets/opencode/herdr-agent-state.js`

A first-class plugin, and correspondingly richer:

```js
export const HerdrAgentStatePlugin = async () => {
  if (process.env.HERDR_ENV !== "1" || !process.env.HERDR_SOCKET_PATH
      || !process.env.HERDR_PANE_ID) {
    return {};                       // same no-op guard, plugin-shaped
  }
  return {
    "chat.message": async ({ sessionID }) => { /* → working */ },
    event: async ({ event }) => {
      switch (event?.type) {
        case "tool.execute.before": case "tool.execute.after":
        case "permission.replied":  case "question.replied":
        case "question.rejected":   case "session.compacted":
          await reportState("working", sessionID); break;
        case "permission.asked": case "question.asked": case "session.error":
          await reportState("blocked", sessionID); break;
        case "session.idle":
          await reportState("idle", sessionID); break;
      }
    },
  };
};
```

Three problems it solves that the shell hooks never face, because it sees a *stream*:

**Child-session contamination.** OpenCode subagents emit events on the same stream. The
plugin tracks them and refuses to let a child overwrite the pane's root session id,
while still projecting their state:

```js
const childSessions = new Set();
const CHILD_EVENT_STATES = new Map([
  ["permission.asked", "blocked"], ["question.asked", "blocked"],
  ["permission.replied", "working"], /* … */
]);
// ...
if (info?.id && info.parentID) { childSessions.add(info.id); }
if (sessionID && childSessions.has(sessionID)) {
  const state = CHILD_EVENT_STATES.get(type);
  if (state) { await reportState(state); }   // note: no session id attached
  return;
}
```

A subagent blocking on a permission genuinely blocks the pane — so report the state —
but it must not become the pane's resumable session.

**Ordering.** A promise chain serializes every request, on top of the monotonic `seq`:

```js
function request(method, params) {
  const pending = requestChain.then(() => requestOnce(method, params));
  requestChain = pending.catch(() => {});
  return pending;
}
```

**Server-global vs pane-local.** A second plugin, `herdr-tui-session.js` registered in
`tui.jsonc`, polls `api.route.current` to learn which session *this pane's TUI* has
selected, reporting it with `session_start_source: "select"`. The event stream is
server-global — `session.created` may belong to a different attached client entirely,
which the plugin comments on directly:

```js
case "session.created":
  // Creation is server-global, so an attached client may own it. The
  // TUI plugin separately reports the root selected in this pane.
```

**Lesson:** when the agent has a client/server split, its event stream answers "what
happened," not "what is this pane showing." You may need two probes.

### 4.5 Hooks fire in contexts you did not intend

Every hook must positively identify its own event. Real cases:

**Claude** — Cursor reuses Claude Code's hook payload shape, so the Claude hook would
fire inside Cursor and report the wrong agent:

```python
if "CURSOR_VERSION" in os.environ or "cursor_version" in hook_input:
    raise SystemExit(0)
hook_event_name = str(hook_input.get("hook_event_name") or "")
if hook_event_name != "SessionStart":
    raise SystemExit(0)
if bool(hook_input.get("agent_id")):     # subagent, not the pane's session
    raise SystemExit(0)
```

**Codex** — requires a transcript path, and refuses when the inherited thread id
contradicts the reported one:

```python
transcript_path = hook_input.get("transcript_path")
if not isinstance(transcript_path, str) or not transcript_path.strip():
    raise SystemExit(0)
inherited_session_id = os.environ.get("CODEX_THREAD_ID")
if inherited_session_id and inherited_session_id != agent_session_id:
    raise SystemExit(0)
```

**Copilot** — normalizes naming conventions, then rejects anything that smells like a
different event:

```python
def normalize_event(event):
    return event.replace("_", "").replace("-", "").lower()
event = first_text("hook_event_name", "hookEventName")
if event:
    if normalize_event(event) != "sessionstart":
        raise SystemExit(0)
elif "prompt" in hook_input or first_text("tool_name", "toolName",
                                          "notification_type", "stop_reason", "reason"):
    raise SystemExit(0)
```

Note the `elif`: when the host gives no event name at all, infer from payload shape and
**bail on ambiguity**. Guessing wrong writes bad state.

**Generalization:** being installed is not proof the current invocation is yours.
Check the event name, check for sibling tools that share your payload shape, check for
sub-invocations, and exit 0 on anything unrecognized.

### 4.6 Installation: editing config you don't own

Herdr writes into directories the user owns and other tools also write to. Code in
`src/integration/` — `registry.rs`, `actions.rs`, `targets.rs`, `config_edit.rs`,
`claude_settings.rs`, `command.rs`, `env.rs`.

**Config directory resolution** goes through one helper
(`config_dir_from_env_or_home`, `src/integration/env.rs`): env var wins if non-empty →
tilde expansion (`~`, `~/`, `~\`) → `home_dir()` + segments, where `home_dir()` is
`$HOME`, then `%USERPROFILE%`, then `HOMEDRIVE`+`HOMEPATH`.

| Agent | Directory | Override |
| --- | --- | --- |
| Claude Code | `~/.claude` | `CLAUDE_CONFIG_DIR` |
| Codex | `~/.codex` | `CODEX_HOME` |
| Copilot | `~/.copilot` | `COPILOT_HOME` |
| OpenCode | `~/.config/opencode` | — |

The messy cases are the instructive ones. Devin (fixed in `3150bd92`) needs
`$XDG_CONFIG_HOME/devin` → `%APPDATA%\devin` on Windows → `~/.config/devin`. Hermes
needs `HERMES_HOME`, then on Windows an explicit `HOME` distinct from `USERPROFILE` →
`$HOME/.hermes`, else `%LOCALAPPDATA%\hermes`. **Expect one bespoke resolver per
tool.**

**"The config directory must already exist."** Install refuses to create it. Its
existence is the evidence the tool is actually installed and has run; creating it would
scatter empty directories for tools the user does not have.

**Four config-ownership strategies**, because hosts differ in what they allow:

1. **Edit a shared JSON file** — claude/copilot `settings.json`, codex `hooks.json`.
   Requires JSONC-preserving surgical edits (`claude_settings.rs`) so comments and
   unrelated keys survive, and uninstall removes only Herdr's entries.
2. **Write a self-contained sibling file** — Grok merges every `hooks/*.json`, so Herdr
   writes `hooks/herdr.json` and **never touches the user's hook files**. The cleanest
   option when the host supports it.
3. **Own one named block** — Antigravity keys `hooks.json` by hook name, so Herdr
   rewrites only its `"herdr"` block.
4. **A fenced comment block** — Kimi's `config.toml` gets
   `# >>> herdr kimi integration` … `# <<<`, the classic shell-rc pattern, for formats
   with no structural place to own.

**Command construction** (`command.rs`): `bash '<path>' <action>` on Unix,
`powershell -NoProfile -ExecutionPolicy Bypass -File "<path>" <action>` on Windows,
plus a base64 UTF-16LE `-EncodedCommand` variant for hosts that mangle quoting.

**Versioning.** Every asset carries `HERDR_INTEGRATION_ID=` and
`HERDR_INTEGRATION_VERSION=N`; `parse_integration_version()` reads them back (stripping
leading `/` and `#` so the same parser works for `.sh`, `.js`, and `.ts`) and
`integration_status_at()` yields `NotInstalled | Current | Outdated`. Current values in
`src/integration/mod.rs`:

```rust
PI=8, OMP=9, CLAUDE=9, CODEX=8, KIMI=7, COPILOT=3, DEVIN=2, DROID=3,
OPENCODE=10, KILO=4, HERMES=5, QODERCLI=3, QWEN=1, CURSOR=1,
ANTIGRAVITY_CLI=3, MASTRACODE=2, GROK=1
```

Per `CLAUDE.md` these are **migration versions relative to the latest released tag**,
bumped once per release, not per commit — so a user upgrading across two releases sees
one migration, not twelve.

Two refinements past a simple version check:

- **Repair detection.** `grok_hook_config_is_valid()` compares the generated
  `hooks/herdr.json` against what is on disk (order-insensitive);
  `opencode_tui_integration_is_valid()` checks both the plugin file version *and* its
  `tui.jsonc` registration. Either failing downgrades status to `Outdated`, so a
  reinstall repairs a half-valid install. Version equality is not integrity.
- **Minimum agent version.** `enforce_agent_version` (`src/integration/version.rs`)
  refuses to install the Kimi hook below `0.14.0`, rather than installing something that
  silently won't fire.

---

## 5. Layer 3 — Session identity and restore

### 5.1 The reference

A hook reports `agent_session_id` or `agent_session_path`; the server stores an
`AgentSessionRef { kind: Id | Path, value }`, persisted as `PaneAgentSessionSnapshot`
(`src/persist/snapshot.rs:113`).

Validation matters, because this value ends up on a command line: max 512 bytes for an
id, 4096 for a path, no control characters, paths must be absolute. Only pi and omp
accept `Path` at all.

### 5.2 Resume is irreducibly per-tool

`src/agent_resume.rs:118-215` is a flat match producing argv. There is no pattern here
— that is the point:

| Agent | argv |
| --- | --- |
| Claude Code | `claude --resume <id>` |
| Codex | `codex resume <id>` — **subcommand, no flag** |
| GitHub Copilot | `copilot --resume=<id>` — **joined with `=`** |
| OpenCode | `opencode --session <id>` |
| Antigravity | `agy --conversation <id>` |
| MastraCode | `mastracode --thread <id>` |
| OMP | `omp --resume=<id>` — the code comments that it has no `--session`, unlike pi |
| Cursor | `cursor-agent --resume <id>` (`cursor-agent.cmd` on Windows) |

Separate flag, joined flag, bare subcommand; called session, conversation, or thread.
Accept that this table is hand-maintained and keep it in one place.

**The trust gate.** `is_official_agent_source(source, agent)` restricts plan generation
to the 17 `herdr:*` source/agent pairs:

```rust
pub fn plan(source: &str, agent: &str, session_ref: &AgentSessionRef) -> Option<AgentResumePlan> {
    if !is_official_agent_source(source, agent) {
        return None;
    }
    // ...
}
```

This is a genuine security boundary. A `custom:` integration can report a session id —
it shows up in the API, it survives a restart, tooling can read it — but it can never
cause Herdr to construct and execute a command line. Untrusted input reaches display,
never `exec`. Pair this with `is_reserved_native_state_source` (§4.3) and the
`--source` namespace is doing real privilege separation.

### 5.3 Replay

On restore, the plan is rebuilt (`src/persist/restore.rs:785`) and stored as
`pending_agent_resume_plan`. `start_pending_agent_resume`
(`src/app/agent_resume.rs:205`) waits for the host terminal theme to settle, spawns a
fresh runtime with the full pane launch env, and **types the shell-quoted argv plus
`\r` into the PTY** — the same mechanism as `agent.start`. Gated by
`[session] resume_agents_on_restore` (default true).

---

## 6. Layer 4 — Driving the agent

A runtime that only observes is half a runtime.

### 6.1 Launch

`agent.start` (`src/app/agents.rs:145`) requires an existing pane already back at its
interactive shell prompt — **it never creates layout**. It rejects control characters
in args, calls `begin_managed_agent` to mark the pane pending with a 3-second settle
delay, and writes the command.

The wait is **client-side**: the CLI pins the pane's `terminal_id` and polls
`agent.get` every 100ms until the named agent is present with a matching terminal and
kind and `interactive_ready == true` (`src/cli/agent.rs:562`). It reports distinct
failures — `agent_name_not_found`, `agent_kind_mismatch`, `agent_not_ready` (blocked at
startup), `agent_start_failed` (exited before interactive), `timeout` — and retries
`agent_pane_busy` for up to 2s while the shell is still initializing.

Keeping the poll in the client means the server never holds a request open across a
30-second agent boot.

### 6.2 Encoding text

`src/app/api_helpers.rs:25-88`:

```rust
pub(super) fn encode_api_text(runtime, text) -> Vec<u8> {
    if runtime.bracketed_paste_enabled() {
        format!("\x1b[200~{text}\x1b[201~").into_bytes()
    } else {
        text.as_bytes().to_vec()
    }
}

pub(super) fn encode_api_submission_parts(runtime, text) -> (Vec<u8>, Vec<u8>) {
    (encode_api_text(runtime, text), runtime.encode_terminal_key(Enter))
}
```

Two decisions:

**Bracketed paste is read from the pane's live DECSET 2004 state**, not from config.
The pane's own parser knows whether the foreground application has enabled it *right
now*. A config flag would be wrong the moment the agent toggles modes.

**Enter is `encode_terminal_key(Enter)` → CR (`\r`), never LF**, and it routes through
the key encoder so it respects the active keyboard protocol (Kitty, modifyOtherKeys).
Hardcoding `\r` works today and breaks the first time an agent negotiates an enhanced
protocol. Note also there is **no `\n` → `\r` normalization** in this path: embedded
newlines are sent literally inside the paste wrapper.

### 6.3 The 300ms gap

```rust
const AGENT_PROMPT_SUBMIT_DELAY: Duration = Duration::from_millis(300);
```
(`src/app/api/agents.rs:13`)

Text and Enter are two writes separated by 300ms, queued as one unit through the PTY
actor (`queue_user_input_submission`), with the API response deferred until the actor
confirms. TUI agents process a paste asynchronously; an Enter arriving in the same
write can be consumed before the paste is ingested, submitting an empty prompt.

This is the kind of thing you only learn from a bug report. Budget for per-agent input
quirks — here is another, in full:

```rust
if expected_agent == crate::detect::Agent::GithubCopilot {
    // Copilot ignores synthetic Enter after focus loss until it receives focus gained.
    let focus = crate::ghostty::encode_focus(crate::ghostty::FocusEvent::Gained)?;
    runtime.try_send_bytes(Bytes::from(focus))?;
}
```
(`src/app/api/agents.rs:152`)

Copilot tracks terminal focus and drops synthetic Enter after focus loss, so Herdr
emits a synthetic focus-gained (`\x1b[I`) first.

### 6.4 Refusal guards

`queue_agent_prompt` checks everything **before writing a single byte**:

| Condition | Error |
| --- | --- |
| empty text | `empty_agent_prompt` |
| state is `Blocked` | `agent_blocked` |
| no known agent in pane | `agent_not_ready` |
| managed launch still pending | `agent_not_ready` |
| agent no longer the pane foreground process | `agent_not_ready` |

The `Blocked` guard is the important one, and it closes the loop with §3.6: detection
biases toward `idle` so it never falsely reports blocked, and input refuses whenever it
*does* report blocked. **Herdr never auto-answers an approval dialog.** I found no
auto-approve path anywhere in `src/`. It detects, notifies (`ToastKind::NeedsAttention`
+ `Sound::Request`, `src/app/actions.rs:144`), rolls the state up pane → tab →
workspace, and hands off to a human. The bundled agent skill goes further and instructs
a driving agent to *ask the user* before answering an approval dialog.

`send_keys` applies the same discipline within a call: it parses **all** keys through
`config::parse_key_combo` first, then writes the concatenated bytes — so an invalid key
in position three means zero bytes written, not a half-sent sequence.

### 6.5 The one read that writes

Worth knowing because it violates the otherwise-strict read/write split.
`src/server/alt_screen_read.rs`: for an idle recognized agent on the alternate screen,
a `recent` text read with `--lines` greater than the screen height will *drive the
agent's own mouse-scroll interface* to page through history, then restore the viewport.
It returns `agent_not_idle` unless the agent is idle. `visible` reads, `detection`
reads, subscriptions, and output waits stay strictly passive.

---

## 7. Observability

Screen scraping is only maintainable if you can see what the matcher saw. Two commands
carry that weight.

**`herdr agent read <target> --source detection`** returns the *exact* snapshot the
manifest engine evaluates. Not the viewport, not the scrollback — the same bytes.
Sources: `visible` (rendered viewport), `recent` (last N rendered rows, soft wraps
intact), `recent-unwrapped` (wraps rejoined), `detection`.

**`herdr agent explain <target> --json`** dumps the full evaluation: agent, final state,
whether screen detection was skipped and why, manifest source and version, cached remote
version, local-override shadowing, the matched rule, visible-evidence flags, **every
evaluated rule with its matcher and region evidence**, the skipped-update reason, and
the idle-fallback reason. Offline mode (`--file screen.txt --agent codex`) replays a
saved fixture against the current engine.

The per-rule region evidence is what makes rule authoring tractable: you can see that
your rule matched the right region and still failed on the third `contains`, instead of
bisecting a TOML file by hand.

Events: `pane.agent_detected` and `pane.agent_status_changed`, available as one-shot
`events.wait` matches or persistent subscriptions with an optional status filter.
`agent.wait --until blocked` is the server-side form, and it pins the pane occupant
(terminal id + name + agent label) so a *replacement* agent cannot satisfy a wait meant
for its predecessor. High-volume kinds like `pane.output_changed` are deliberately
excluded from the plugin hook event set.

The manifest development loop, from `CLAUDE.md`:

```
agent read --source detection    # see the exact snapshot
agent explain --json             # see which rules fired and why
edit ~/.config/herdr/agent-detection/<label>.toml
herdr server reload-agent-manifests
```

Hot reload without restarting the server is what makes screen scraping a tractable
maintenance activity rather than a compile-cycle-per-guess slog.

---

## 8. Reimplementation checklist

### Build in this order

1. **PTY panes with a real terminal parser.** Everything sits on top of a correct
   emulator with a screen model you can read cell-by-cell.
2. **Foreground process identification** via the pane's tty process group, plus an env
   hint escape hatch read from the target process's environ.
3. **The detection snapshot** — bottom-anchored, one screen tall, plain text, with a
   content sequence number so you can skip unchanged screens.
4. **The manifest engine** — regions, gates, priority, four states.
5. **`explain` output.** Build it *with* the engine, not after. Rule authoring without
   it is guesswork.
6. **The env contract and reporting API** for push-based integrations.
7. **Session identity and per-tool resume argv.**
8. **The input path** — bracketed paste from live terminal state, CR not LF, a
   submit delay, and refusal guards.
9. **Remote manifest distribution.** Last, but design the version discipline early.

### Copy nearly verbatim

- The four-state vocabulary and the `done` = idle + unseen derivation.
- The gate grammar. It is small, sufficient, and its semantics are already debugged.
- The region set, especially `bottom_non_empty_lines(N)` and
  `whole_recent_without_current_prompt_marker`.
- The hook script skeleton: banner, stdin-to-temp-file with trap, env guards, fail-open
  everywhere, 500ms timeout, monotonic seq.
- The `--source` namespace as a privilege boundary.
- The idle-confirmation debounce constants (3 confirmations / 700ms).

### Irreducibly per-tool — budget for it

- Executable names and aliases, including launcher shims and `.cmd` wrappers.
- Config directory resolution. Expect one bespoke resolver per tool, per platform.
- Which config file to edit and how to own part of it without clobbering the user.
- Resume argv. Every tool spells it differently.
- Input quirks (Copilot's focus-gained).
- The manifest itself. Nobody can write this for you; it comes from staring at the real
  UI in every state.

### Design decisions worth adopting

- **Four states, not five.** "Waiting for input" is `blocked`.
- **Fail toward `idle`.** An unmatched screen is never a guessed `blocked`.
- **One authority per pane.** A hook earns state authority only by covering the whole
  lifecycle; a partial hook is worse than none, so demote it to session-identity-only.
- **Enforce that at the boundary,** with an explicit reserved-source list, not by
  convention.
- **Detection reads the live bottom of the buffer,** so users can scroll freely.
- **Never auto-answer an approval prompt.** Detect, notify, refuse input, hand off.
- **Separate session identity from state.** Most integrations can supply the first
  reliably and the second only partially — let them do the part they are good at.
- **Make rules data, not code,** and ship them out of band. Agent UIs change faster
  than your release cadence.
- **Cap everything that comes from the network,** because it is evaluated on a hot path.
- **Gate on invariant controls, not prose.** Footer key hints are the contract.

---

## Appendix — documentation drift found while writing

`docs/next/website/src/content/docs/integrations.mdx` states integration versions that
no longer match the constants in `src/integration/mod.rs`:

| Agent | Docs | Code |
| --- | --- | --- |
| Claude Code | 6 | `CLAUDE_INTEGRATION_VERSION = 9` |
| Codex | 5 | `CODEX_INTEGRATION_VERSION = 8` |
| Copilot | 2 | `COPILOT_INTEGRATION_VERSION = 3` |
| OpenCode | 5 | `OPENCODE_INTEGRATION_VERSION = 10` |
| Kilo Code CLI | 1 | `KILO_INTEGRATION_VERSION = 4` |
| Droid | 2 | `DROID_INTEGRATION_VERSION = 3` |
| Kimi | 3 | `KIMI_INTEGRATION_VERSION = 7` |
| Pi | 2 | `PI_INTEGRATION_VERSION = 8` |
| OMP | 3 | `OMP_INTEGRATION_VERSION = 9` |
| Antigravity | 1 | `ANTIGRAVITY_CLI_INTEGRATION_VERSION = 3` |
| Qoder | 2 | `QODERCLI_INTEGRATION_VERSION = 3` |
| MastraCode | 1 | `MASTRACODE_INTEGRATION_VERSION = 2` |

The prose sentence in question is the "Native session restore requires current Herdr
integrations: … Claude Code version `6`, Codex version `5` …" paragraph. Since users
compare these against `herdr integration status`, the stale list will read as a
mismatch. Flagged, not fixed — a `docs/next` edit is separate work from this report.
