# git-radar

Answers one question: **where did I leave each of my repositories?**

    prefix + t  then  R     one row per tmux session, live, in a normal pane

```
 ● dev-environment
   main ⇡4 ~6 ?2
▎● Portal
▎  feature/relatorios ⇣1
 ● scratch
   no-upstream-branch local +1
 · notes
   not a repo
```

The blue rail down the left marks **the session you are in**, drawn along both
lines of the entry so the whole row reads as the one you are standing in.

It needs a channel of its own because every other one is taken: the marker's
colour is the state, bold is the selected row, and the background is the
selection band. Blue is the one hue neither a state nor a counter claims, so it
cannot be misread as either.

It is not the same thing as the selection, and the difference matters: the band
says where your *cursor* is, the rail says where you *are*. Since the band only
appears while the pane has focus, a feed you are merely glancing at from another
pane has no band on screen at all -- and the rail is then the only thing
answering "which of these am I in?".

Which session that is comes from `$TMUX_PANE`, the pane the feed was started in,
not from the attached client. The two agree whenever you can see the pane, and
they disagree exactly when you have switched the client elsewhere -- at which
point the row worth marking is still the one this pane lives in. It is resolved
once at startup, so it costs nothing per refresh, and it is a consumer's
question rather than a published field: the sampler is detached and belongs to
no session.

    ⇡  commits to push (cyan)      +  added (green)       ?  untracked (grey)
    ⇣  commits to pull (magenta)   ~  modified (yellow)   !  conflicted (red)
                                   -  deleted (red)

**A counter appears only when it is non-zero.** A row of `+0 ~0 -0 ?0` has to be
read before it can be dismissed; a lone green `+2` does not. What is left on the
row is only what is true, so a clean repository is just a name and a branch.

Green added, yellow modified, red deleted, grey untracked is the vocabulary
every diff already uses, so it needs no learning. The two arrows take cyan and
magenta rather than the green/red many prompts give them, so that green and red
keep meaning "added" and "deleted" and nothing else on the row.

**The marker carries the state** -- red conflicted, magenta diverged (ahead *and*
behind), yellow dirty, cyan committed-but-unpushed, green clean, grey not a
repository. It is the only thing always in the same place, so it is what the eye
lands on first, and it is dimmed for the states that want nothing from you: a
bright dot on every clean repository is the "always present, therefore ignored"
problem that keeps clean agents out of the status bar.

**Two lines per session.** One line per session was the first attempt, and in a
35%-wide pane it padded every column to the width of the widest row, which is
what made the whole thing read as a single grey block. Two lines let each row be
exactly as wide as it needs to be. When the pane is narrower than a row, the
branch name is truncated before the counts are -- the counts are the point.

`local` marks a branch with no upstream. Without it, "show only non-zero
counters" would render a branch you have never pushed identically to one that is
fully in sync -- the one case where an absent arrow means the opposite of what it
usually does.

Keys: `j`/`k`/`g`/`G` move, `Enter` switches to the session, `r` refreshes now,
`f` fetches the selected repository, `Ctrl-C` closes the pane.

`Ctrl-C` and nothing else, deliberately. A feed is a pane you leave open and
type past, so closing it should take a gesture you cannot make by accident: `q`
is one fumbled pane away and `Esc` is muscle memory from vim. Both used to close
it and no longer do.

**The highlight follows the focus.** A feed is something you glance at from
another pane, so a selection band sitting there permanently is a cursor you
cannot move competing with the rows for attention. It appears when the pane has
the focus and disappears when it loses it, using the terminal's own focus
reporting (`CSI ?1004h`) which `focus-events on` in `modules/tmux/common.conf`
makes tmux forward. Polling tmux instead would have cost about 14ms per ask --
more per feed pane than sampling the whole machine does.

The second line is dim whether or not its row is selected. It is secondary by
definition, and brightening it on selection made the highlight shout twice.

## The two constraints that shape it

**It never fetches on its own.** Ahead/behind comes from the origin refs already
in the repository. A tick therefore costs no network, cannot hang on a remote
that is down, and cannot block on credentials -- which matters a great deal for
something a daemon runs every few seconds across every session you have open.

The cost is honest and worth naming: *behind* is only as fresh as your last
fetch. `f` fetches the selected repository on demand, on a background thread so
the pane never freezes, and the counts update on the next tick.

**One `git status` per repository.** `--porcelain=v2 --branch` returns the
branch, the upstream *and* the ahead/behind pair in its header lines, so a
repository does not cost a `status` plus a `rev-list`. Sessions sharing a
repository share its call. Everything runs under `--no-optional-locks`, so the
daemon never takes `index.lock` and never loses that race against your own
interactive git.

## Rows are in session order, not urgency order

agent-radar sorts blocked agents to the top, because you open that list to find
the one agent that needs you. This list is different: it doubles as your session
list, and a row that jumps while you are reaching for Enter is worse than one
you have to scan for. Attention is carried by colour instead.

Sorting by `STATE_ORDER` instead is a one-line change in `git_radar.detect()` --
the feed anchors its cursor by session name and tolerates re-ordering.

## Session to directory

`#{session_path}` -- where the session was created, which is what
`New-CodeSession.sh` sets to the project directory. Deliberately not
`#{pane_current_path}`: a session's identity is its project, not wherever the
shell in pane 2 happens to have `cd`'d. `pane_current_path` is only the fallback
for sessions created without an explicit `-c`.

A session whose directory is not a work tree still gets a row, dimmed, saying so
where its branch would be. It shows no counters at all rather than zeros --
"0 modified" would assert a clean work tree for a directory that has none.

## How it works

```
Start-GitRadar.py     the daemon. One sampler for the whole machine.
  git_radar.py        collector: list_sessions -> repo_root -> inspect
  git_feed.py         binds the shared cache to Repo rows, at a 3s tick
  Get-GitState.py     presentation + CLI (table / tsv / json / fzf / status)
Watch-GitFeed.py      the curses feed on prefix + t then R. Reads, never samples.
```

The daemon is nobody's responsibility to start. The first consumer that finds
the lock free spawns it, and it exits on its own once tmux is gone or nothing
has read from it for 90 seconds. A consumer whose read comes back stale samples
live instead, so a dead or slow daemon degrades to the old cost rather than to
an empty list.

The machinery behind that -- cache directory, atomic publish, flock liveness,
heartbeat, staleness rules -- is **shared with agent-radar** and lives in
[`modules/tmux/scripts/radar_cache.py`](../tmux/scripts/radar_cache.py). So is
the drawing: the colour palette, the selection band and the truncation rule are
in [`radar_ui.py`](../tmux/scripts/radar_ui.py) beside it, which is why both
feeds look the same. It sits
there rather than inside either radar because it belongs to neither. See
[agent-radar's README](../agent-radar/README.md) for the two bugs that produced
it: sampling cost multiplying by the number of open consumers, and cross-sample
smoothing silently breaking once more than one process was sampling.

`git_feed.py` ticks at **3 seconds**, not agent-radar's 1. A tick here walks the
work tree; a tick there is a `capture-pane`. And the latency that matters is
different -- a blocked agent is waiting on you *now*, whereas a file you just
saved can appear a moment later without anyone noticing.

## Trying it without tmux bindings

```bash
~/.modules/git-radar/scripts/Get-GitState.py                 # sampled live
~/.modules/git-radar/scripts/Get-GitState.py --cached        # the shared snapshot
~/.modules/git-radar/scripts/Get-GitState.py --format=json
~/.modules/git-radar/scripts/Watch-GitFeed.py                # the feed, in this pane
```

There is no status-bar segment. The daemon publishes a summary string anyway
(`--format=status`), so adding one is the same one-line `run-shell` that
agent-radar uses in `modules/tmux/tmux.conf`.
