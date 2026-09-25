# scripts

Your own scripts, kept under version control and one chord away.

    prefix + s              pick one, run it in a pane on the right
    prefix + -  then  s     the same, in a pane below
    prefix + S              the same, run inside the picker's popup

```
  script> back
  Run script   (ctrl-r refresh)
> Backup-Database.sh   bash    Dumps the local database into ~/backups
  Show-Example.ps1     pwsh    The same example in PowerShell
  Show-Example.sh      bash    Prints where and how it ran
```

## Adding one

Drop it in `library/` and commit. That is the whole procedure.

There is no registry to keep in step and no metadata file: a script is listed
because it is there, and it is described in the list by **its own first comment
line** -- the same header every script in this repo already opens with. A file
that starts with code instead simply has no description.

    #!/usr/bin/env bash
    # Dumps the local database into ~/backups.     <- this line

`~/.modules` is a symlink to this repository on the host (`LinuxDevEnv/host-setup.sh`),
so a committed script is live in the next popup without re-running any setup. In
the container the module is `COPY`-ed in at build time like every other one.

## Keeping one to yourself

**Start the name with a dot.** The root `.gitignore` drops
`modules/scripts/library/.*`, so a hidden script never reaches this repository
-- while the picker lists it exactly like the rest:

    .Deploy-Staging.sh   bash    Ships the current branch to staging

That is the whole difference: the dot decides what **git** sees, not what you
can run. Use it for anything machine-specific, half-finished, or that names
something which has no business in a public repo.

Hidden scripts are yours to keep alive, though -- nothing backs them up and a
fresh machine starts without them.

## Running one

`scripts/Invoke-Script.sh` works out how, so a library script needs neither an
executable bit nor a shebang:

| File | Run with |
|---|---|
| `*.sh` | `bash` |
| `*.ps1` | `pwsh -NoProfile -File` |
| `*.py` | `python3` |
| anything else | its shebang, or `bash` if it has none |

It is a normal script, so it is also the sane way to run one by hand:

```bash
~/.modules/scripts/scripts/Invoke-Script.sh ~/.modules/scripts/library/Backup-Database.sh
```

The pane closes on a keypress rather than the moment the script ends. Panes
opened by these bindings die with their command (`closing_line` in
`modules/tmux/scripts/tmux-helpers.sh`), which for a script that finishes in a
second would mean never seeing what it printed.

## Where it runs

In the pane's current directory -- the picker splits the pane you fired it from,
so a script that works on "the repository I am in" gets the one you are looking
at. In an ssh session (`prefix + N`) it runs on the **remote**, in that session's
directory, like every other tool pane. The list is then the **remote's** library,
read from its own clone of this repository, so what you pick is what is there to
run -- a hidden script kept on this machine is not offered on the other one. A
remote without this dev-environment has no library, and the picker says so.

## Files

| Path | Role |
|---|---|
| `library/` | the scripts; everything here is listed |
| `scripts/Select-Script.sh` | the fzf picker behind the two bindings |
| `scripts/Invoke-Script.sh` | interpreter detection, the run, and the pause |

The two `Show-Example` files are there to show the shape and to prove both
interpreters are picked up. Delete them once you have scripts of your own --
nothing refers to them.
