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
`f` fetches the selected repository and `F` fetches every listed one, `p` pulls
it and `P` pushes it, `q` kills the selected session after asking, `Ctrl-C`
closes the pane.

**The cursor is on your row when you arrive.** Every session runs a feed of its
own, so the row worth having under the cursor in it is that session's -- the
same one the rail marks. It starts there and is put back there on every switch
into the session. The pane cannot see the switch by itself: it is not the pane
that gains the focus, so no focus event reaches it, and asking tmux every tick
whether the session is attached would cost the 14ms per pane per tick that the
focus events below exist to avoid. A `client-session-changed` hook in
`modules/tmux/common.conf` runs `Sync-RadarSelection.sh`, which sends the feed a
single reserved keypress instead.

**`Enter` goes on into NeoVim when the session is sitting on a radar pane.**
Pressing it there is a request to stop reading the list and start working, and
on your own row -- where the cursor now starts -- `switch-client` alone does
nothing at all, so it would otherwise be a dead key on the row you press it on
most. A session parked on a terminal or an agent is left exactly as you left it:
arriving somewhere other than where you were is worse than one extra `C-l`. The
editor is found by its `@pane_label`, not by pane index -- the index is an
accident of the order `Set-NeovimLayout.sh` splits in.

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
the pane never freezes, and the counts update on the next tick. `F` does the same
for every session listed, four at a time. `p` and `P` -- the pull and the push
described below -- are the other two commands this pane will run, and everything
in the next paragraph is true of all three.

**None of the three is given any way to ask you anything.** `f`, `p` and `P` all
run under `BatchMode` with no stdin and no controlling terminal, so they cannot
prompt for a passphrase or a password; one that would have needed a credential
fails in milliseconds and its row says `unable to fetch` -- or `pull`, or `push`
-- for a few seconds.

That is not politeness, it is the only way this can be correct. Capturing a
fetch's output does not keep a prompt off the screen: `ssh` does not ask on
stdout or stderr, it opens `/dev/tty` and writes straight to the pane. curses
repaints differentially and has no idea those cells were touched, so it never
paints over them -- the prompt stays welded to the pane for the rest of its life.
Closing every prompt path is what makes `F` cheap too: "fetch everything, skip
whatever would have asked" needs no detection pass when nothing *can* ask.

The prompt has to happen somewhere, so a failure you asked for by name -- `f`,
`p` or `P`, but never one of the many that an `F` starts -- opens a popup with
git's full message. When the failure was an authentication one, the popup offers
to unlock the key this host would have tried for that remote and does not already
hold, and retries. The retry is the operation that failed, not always a fetch: a
passphrase is just as likely to be what stopped a push.

The passphrase is typed in the popup, which is its own pty and takes any mess
away with it when it closes. It is asked at most once: the key goes into the
agent, so every later fetch, pull or push finds it there. Nothing is unlocked at
login, and a key that is already loaded is never asked for again.

**One `git status` per repository.** `--porcelain=v2 --branch` returns the
branch, the upstream *and* the ahead/behind pair in its header lines, so a
repository does not cost a `status` plus a `rev-list`. Sessions sharing a
repository share its call. Everything runs under `--no-optional-locks`, so the
daemon never takes `index.lock` and never loses that race against your own
interactive git.

## `p` pulls and `P` pushes

The two counters this pane spends most of its time showing were the two it could
do nothing about: it would tell you a repository was four commits behind and then
send you elsewhere to act on it. `p` and `P` clear a `⇣` or a `⇡` where you read
it.

**Both act on the selected row and only on it.** There is deliberately no
shifted all-rows twin to match `F`. `F` is affordable because a fetch changes
nothing locally and one that cannot authenticate costs milliseconds; "pull every
repository on this machine" is a work tree changed in a dozen places from one
keystroke, and there is no version of that whose failures a row can honestly
summarise.

**`p` is `pull --ff-only`.** It fast-forwards or it refuses, which is what makes
it safe to press in a pane you are only glancing at: it can never open a merge,
never leave a conflicted tree and never want an editor -- and an editor is
precisely what the no-tty rule above makes impossible to answer. A row that
cannot fast-forward says `cannot fast-forward` and you go and do it in NeoVim,
where you can see the conflict.

**`P` sets the upstream when there is none**, rather than refusing: publishing a
branch you have never pushed is the main thing `P` is wanted for on the rows
marked `local`, and that marker disappearing on the next tick is the
confirmation. It does not ask first, unlike the `q` beside it: a push is one
`--force-with-lease` away from undone, and killing a session is not.

Two refusals are answered from the row already on screen rather than from the
network -- `no upstream` for a `p` on a `local` branch, `detached HEAD` for
either on a detached one. git would say the same thing in a paragraph, several
seconds and one ssh connection later.

Only one of the three runs in a repository at a time, and the guard is keyed by
*repository root* rather than by session, because the root is what has an
`index.lock` to fight over -- two sessions in one repository share it. A key
pressed on a busy row does nothing rather than queueing: the row is already
saying what it is doing, and a second command you did not notice starting is
worse than a keypress that visibly did not take.

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
                      (and request_sample, for when 3s is too long to wait)
  Get-GitState.py     presentation + CLI (table / tsv / json / fzf / status)
Watch-GitFeed.py      the curses feed on prefix + t then R. Reads, never samples.
  Show-GitFailure.sh  the popup a named f/p/P failure opens: the message, and
                      an offer to unlock the key it wanted and retry.
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

### Except when you did something, where three seconds is far too long

The tick is the rate this falls back on when nothing tells it anything. It is
the wrong answer entirely for the changes *you* just made, and killing a session
with `q` is the worst of them: the session is gone the instant you answer `y`,
and the row for it used to sit there for **two seconds** afterwards. Long enough
to wonder whether the key worked, which is how you end up killing a second
session by pressing it again.

`q` did already try. It set the feed's next-sample deadline to zero, and it
could not work, for a reason worth keeping written down: **what a consumer reads
is the published snapshot, and the snapshot is exactly the thing that is out of
date.** Forcing a re-read only re-read the sampler's last answer, taken before
the kill. The force has to reach the sampler, and the sampler is another
process.

So three things happen when you answer `y`, in this order, because only the
first is instant:

    1. the row is dropped from this pane's own list        0ms
    2. the sampler is asked to publish now, not in 3s      ~150ms for everyone else
    3. this pane redraws when that publication lands       within one getch

Dropping the row locally is a *guess about what the sampler will say*, and the
sampler stays the authority: if the kill somehow failed, the next sample brings
the row straight back. That is the right way round -- a row that flickers back
is a bug report, where a row that never leaves is one you learn to ignore.

Measured, killing a session from the feed with `q`,`y`: **2.1s before, 0.09s
now**. A session closed from anywhere else -- an `exit` in its last pane, a
`tmux kill-session` from a shell -- goes through the tmux hooks in
[`modules/tmux/common.conf`](../tmux/common.conf) instead, which touch the same
flag: **1.3s before, 0.2s now**.

The same applies to `f`, `p` and `P`: a finished fetch has moved the refs, and
the counts on screen cannot change until something samples the repository
again. And to `r`, where "refresh now" that returns identical numbers is
indistinguishable from a dead key.

The machinery is [`radar_cache.py`](../tmux/scripts/radar_cache.py) --
`request_sample()` touches a flag, `wait_for_tick()` is what the sampler sleeps
in, and `generation()` is the snapshot's mtime, which the feed watches instead
of running a timer of its own. agent-radar's feed uses all three the same way,
and [its README](../agent-radar/README.md) has the longer version of why the
flag is a file's mtime rather than a signal.

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
