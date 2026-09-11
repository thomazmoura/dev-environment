---
name: tmux
description: "Control tmux, the terminal multiplexer this environment runs coding agents in. Use only when the user explicitly mentions tmux or asks to use tmux to inspect or control panes, windows, sessions, commands, or another agent. Do not use merely because a task could benefit from a background terminal, delegation, or parallel work. Requires TMUX and TMUX_PANE."
---

# tmux

tmux organizes terminals into sessions, windows, and panes. In this environment every project gets its own session, and coding agents run in panes beside the editor. tmux itself knows nothing about agents; agent state comes from agent-radar, which reads each agent pane's screen (see below).

Before issuing any control command, verify that this agent is running inside a tmux pane:

```bash
test -n "${TMUX:-}" && test -n "${TMUX_PANE:-}"
```

If the check fails, say that you are not running inside tmux and stop. Do not attach to, or control, a tmux server from outside it.

When the check passes, the `tmux` binary in `PATH` talks to the server that owns this pane.

## Learn the current CLI

The installed binary is the authority for command syntax:

```bash
tmux -V
tmux list-commands             # every command with its usage line
tmux list-commands split-window
man tmux                       # FORMATS section lists every #{variable}
```

Do not run bare `tmux`, `tmux new`, or `tmux attach` for discovery: they create or attach a client and take over the terminal. Every command used below is non-interactive.

## IDs and caller context

tmux gives every object a unique ID that never changes and is never reused while the server is running:

- session: `$3`
- window: `@12`
- pane: `%27`

Always target by ID. Indexes (`session:1.2`) shift when windows or panes are created, closed, or moved, and names can collide. Quote IDs in the shell: `$3` would otherwise expand.

The calling pane is `$TMUX_PANE`. **Every command must carry an explicit `-t`.** Without it, tmux resolves the target from the most recently active client, which is whatever pane the user is looking at right now, possibly in another session.

Discover live state:

```bash
tmux display-message -p -t "$TMUX_PANE" '#{session_id} #{session_name} #{window_id} #{pane_id} #{pane_width}x#{pane_height} #{pane_current_path}'
tmux list-panes -s -t "$TMUX_PANE" -F '#{pane_id} #{window_id} #{pane_width}x#{pane_height} #{pane_current_command} #{@pane_label}'
tmux list-sessions -F '#{session_id} #{session_name} attached=#{session_attached}'
```

`list-panes -s` lists the current session; `-a` lists every session on the server. Creation commands print the new ID when given `-P -F '#{pane_id}'`; read IDs from that output instead of predicting them.

## Open a pane

Default to a sibling pane in the current window and the current working directory. Do not create a session or window, or use a different cwd, unless the user explicitly requests that.

Honor a direction the user asked for. Otherwise check the caller's geometry: split a wide pane side by side (`-h`) and a narrow or tall pane top/bottom (`-v`). Avoid repeated same-direction splits that leave unusably thin columns or rows.

```bash
pane=$(tmux split-window -h -d -t "$TMUX_PANE" -c "$PWD" -P -F '#{pane_id}')
tmux select-pane -t "$pane" -T "Tests"
tmux set -p -t "$pane" @pane_label "Tests"
```

- `-d` keeps the user's focus in the calling pane.
- `-c "$PWD"` preserves the working directory; without it the pane starts wherever the server was started.
- Label every pane you create, twice: `select-pane -T` is the border title, and `@pane_label` is what this environment's pane picker and border format read. Programs overwrite the title with OSC 2, but the option persists.

The new pane runs the default shell (`#{pane_current_command}` shows `bash` or `pwsh` when it is at a prompt). Give it a moment to draw its prompt before typing into it.

## Run an ordinary command

Type text with `send-keys -l` and submit with a separate `Enter`. `-l` sends the text literally; without it a word such as `Enter`, `Space`, or `C-c` is interpreted as a key.

To wait for the command, have the pane signal a channel when it finishes. `wait-for -S` is latched: a signal sent before anyone waits is kept until the next wait consumes it, so there is no race.

```bash
channel="done-${pane#%}-$$"
tmux send-keys -t "$pane" -l -- "just test; tmux wait-for -S $channel"
tmux send-keys -t "$pane" Enter
timeout 120 tmux wait-for "$channel"
```

`;` works in both bash and pwsh, so the signal fires whether the command succeeded or failed. Always wrap the wait in `timeout`; a bare `wait-for` blocks forever if the command never finishes. If you need a specific output rather than completion, poll `capture-pane` for it with a timeout instead.

Read the result:

```bash
tmux capture-pane -p -J -t "$pane" -S -120
```

Choose what to capture:

- no `-S`: the visible screen only.
- `-S -N`: the last N lines of scrollback plus the screen; `-S -` is the whole history.
- `-J`: join soft-wrapped lines; prefer it for logs and transcripts.
- `-e`: keep ANSI colours, when styling is evidence.

`capture-pane` returns the live screen even while a human has the pane in copy mode.

If raising `-S` does not reveal more of a completed response, the program is drawing on the alternate screen, whose rows never enter scrollback. Ask it to write its full answer as Markdown to a temporary file and reply with only the path, then read the file. Use this only as a fallback.

## Start and coordinate an agent

Open a sibling pane as above, labelled with the agent's name, and check that it is sitting at a shell prompt:

```bash
tmux display-message -p -t "$pane" '#{pane_current_command}'   # bash / pwsh / zsh
```

Then start the agent the user asked for (`claude`, `codex`, `copilot`, `opencode`) the same way as any command, passing its native arguments on the command line:

```bash
tmux send-keys -t "$pane" -l -- "codex"
tmux send-keys -t "$pane" Enter
```

### Agent state comes from agent-radar

agent-radar identifies the agent in each pane from the process tree and classifies its screen. It prints one tab-separated row per agent pane, `pane_id session window label agent state detail`:

```bash
python3 ~/.modules/agent-radar/scripts/Get-AgentState.py --format tsv --cached \
  | awk -F'\t' -v p="$pane" '$1 == p'
```

`--format json` gives the same fields, plus the `rule_id` that matched. The states:

- `working`: the agent is busy.
- `blocked`: it is showing an approval or question dialog and needs a keystroke.
- `idle`: ready for input.
- `done`: `idle` after finishing work that no client has displayed yet. Treat it exactly like `idle`.
- `unknown`: an agent is present but no rule matched. It does not prove completion.

No row at all means agent-radar does not see an agent in that pane: it has not started yet, or it exited.

Always use `--cached`. It reads the snapshot the background sampler publishes once a second and starts the sampler if none is running. Do not poll with `--debounce` or live sampling: the debounce keeps its history in a shared file, and a second sampler corrupts it for every other reader.

### Wait until the agent settles

Wait for the agent to appear and reach `idle` before prompting it. After a prompt, wait for it to have been seen `working` and then leave that state; otherwise the check passes before the agent has picked the prompt up.

```bash
agent_state() {
  python3 ~/.modules/agent-radar/scripts/Get-AgentState.py --format tsv --cached \
    | awk -F'\t' -v p="$1" '$1 == p { print $6 }'
}

# after sending a prompt: wait up to 20s for work to start, then up to 10 min for it to end
for _ in $(seq 20); do [ "$(agent_state "$pane")" = working ] && break; sleep 1; done
for _ in $(seq 600); do
  case "$(agent_state "$pane")" in working) sleep 1 ;; *) break ;; esac
done
agent_state "$pane"
```

If work never starts, read the pane before retrying: the prompt may still be sitting unsubmitted in the input box.

### Send a prompt

Check the state first. If it is `blocked`, do not send anything: read the pane, show the user what the dialog is asking, and let them decide how to answer.

Send the prompt as a bracketed paste, so a multi-line prompt stays one prompt instead of submitting at its first newline, then submit it after a short delay:

```bash
tmux set-buffer -b agent-prompt -- "Review the current diff and report only actionable findings."
tmux paste-buffer -p -d -b agent-prompt -t "$pane"
sleep 0.3
tmux send-keys -t "$pane" Enter
```

`-p` wraps the text in bracketed-paste markers when the program has asked for them, and `-d` deletes the buffer afterwards.

Send interface keys by name, without `-l`:

```bash
tmux send-keys -t "$pane" Escape
tmux send-keys -t "$pane" C-c
```

Read the agent's answer with `capture-pane -p -J -S -200`. If a wait ends in `blocked`, capture the pane and ask the user before sending any keystroke.

## Safety and coordination rules

- Keep `-d` on `split-window` and `new-window`. Do not `select-pane`, `select-window`, or `switch-client` unless the user asked to move their focus.
- Pass `-t` with an ID on every command. Never rely on the current client's pane.
- Parse IDs from command output. Do not derive them from indexes, examples, or the order of a listing.
- Do not kill panes, windows, or sessions you did not create unless the user explicitly asked. Close your own with `tmux kill-pane -t "$pane"` when the work is done and its output has been read.
- Never run `kill-server`, and never kill a whole session the user is using.
- Do not change server state that affects the user: no `source-file`, no global `set -g`/`set-option -g`, no `bind-key`, no `set-hook`. Pane-scoped options (`set -p`) on your own panes are fine.
- Before typing into a pane you did not create, check `#{pane_current_command}` and capture its screen. Keystrokes land in whatever is in the foreground, including an editor or another agent.
- A failing tmux command prints its error on stderr and exits with status 1.
