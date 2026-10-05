# Git pane keys

Every key acts on the selected row's repository. On a row of an ssh session
(prefix+N), the popups run on that host.

## Move

| Key | Does |
|---|---|
| `j` / `k` | Down / up (arrows too) |
| `g` / `G` | First / last row |
| `Enter` | Switch to the row's session (into NeoVim from a radar pane) |

## Sync

| Key | Does |
|---|---|
| `f` | Fetch the selected repository |
| `F` | Fetch every listed repository |
| `p` | Pull |
| `P` | Push |

## Popups

| Key | Does |
|---|---|
| `c` | Commit: shows the status, `y` stages everything and commits |
| `C` | Check out another branch, picked with fzf (`gitco`) |
| `s` | Status, read-only |
| `h` | History: the commit graph, `q` closes |
| `m` | Merge this branch into another, push it, come back |

## Sessions

| Key | Does |
|---|---|
| `H` | Mark the row's session as home (`prefix+h`), or unmark it |
| `q` / `d` | Kill the row's session, after asking (`y` confirms) |

## Pane

| Key | Does |
|---|---|
| `r` | Reload the feed |
| `R` | Reload and restart the sampler |
| `?` | This list |
| `Ctrl-C` | Close the pane |
