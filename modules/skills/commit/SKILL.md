---
name: commit
description: Stage and commit pending changes, one commit per group of related changes, with auto-generated messages
model: sonnet
disable-model-invocation: true
allowed-tools: Bash(git add *) Bash(git status *) Bash(git diff *) Bash(git commit *) Bash(git log *) Bash(git restore --staged *) Bash(rg *) Read(CHANGELOG.md) Edit(CHANGELOG.md) AskUserQuestion
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`
- Latest CHANGELOG entry: !`rg -m1 -n '^## \[' CHANGELOG.md || echo 'no CHANGELOG.md with hash entries'`

## Your task

Based on the above changes, create one git commit per group of related changes (plus a changelog
commit, see step 7):

1. Stage all changes, including new files, using `git add .`
2. Scan what is now staged for sensitive information. Run both commands exactly as written:

   ```
   git diff --cached --name-only | rg -i -e '(^|/)\.env(\.|$)' -e 'id_(rsa|ed25519|ecdsa)' -e '\.(pem|key|p12|pfx|keystore)$' -e 'credentials' -e 'secrets?\.'
   ```

   ```
   git diff --cached -U0 | rg '^(\+\+\+ b/|\+[^+])' | rg -i -e '^\+\+\+ b/' -e 'BEGIN [A-Z ]*PRIVATE KEY' -e 'AKIA[0-9A-Z]{16}' -e 'gh[pousr]_[A-Za-z0-9]{30,}' -e 'sk-[A-Za-z0-9_-]{20,}' -e 'xox[abprs]-' -e 'eyJ[A-Za-z0-9_-]{10,}\.eyJ' -e '(password|passwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)\W{0,3}[:=]\W{0,3}\S{6,}' -e '://[^/\s:@]+:[^/\s@]+@' -e '/home/[a-z0-9._-]+/' -e '/Users/[^/]+/' -e 'C:\\Users\\' -e '/srv/' -e '/var/www/' -e '\b(10\.\d+|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+\b'
   ```

   - The first flags files that usually hold secrets (`.env`, private keys, credential files).
     Exit code 1 with no output means nothing matched — that is a clean result, not an error.
   - The second prints each staged file header (`+++ b/<file>`) followed by any added lines that
     look like keys, tokens, passwords, credentials in URLs, absolute user or server paths, or
     private IPs. Headers with no line under them are clean.
   - Also read the added (`+`) lines in the context diff — and in `git diff --cached` for newly
     added files, which the context diff does not show — for anything the patterns cannot catch:
     internal hostnames or domains, hard-coded connection strings, real people's emails or
     personal data, customer data.
   - Judge each hit: a `~/` path, an obvious placeholder (`example.com`, `changeme`, `xxx`) or a
     variable read from the environment is fine. A literal secret value or a machine-specific
     absolute path is not.
3. If anything real was flagged, do NOT commit. Call `AskUserQuestion` listing every finding as
   `file — snippet (why)`, with secret values partly masked (e.g. `abcd…5678`), and offer:
   - "Abort — I'll fix it" (Recommended): stop here, leave the index as is, make no more calls
   - "Unstage flagged files, commit the rest": `git restore --staged <files>`, then continue
   - "Commit anyway (false positive)": continue

   If the user answers with free text, follow it.
4. Group what is now staged (`git diff --cached --name-status`) into related changes. A group is
   one purpose: a feature, a fix, a refactor, a config or dependency bump. Changes belong together
   when they serve the same purpose, whatever part of the code they are in: a feature that touches
   the backend, the frontend, its tests and its docs is one group. Changes are unrelated when
   each would make sense, and could be reverted, without the other. When unsure, keep them
   together. Splitting is by file: a file that holds changes for more than one group goes in the
   group most of its changes belong to. A rename's old and new paths go in the same group.
   Leave out any file unstaged in step 3. With a single group, this is one commit, as before.
5. Write a concise commit message for each group:
   - Imperative mood (e.g., "Add feature", "Fix bug", "Update config")
   - First line under 72 characters
   - **IMPORTANT!** No reference to Claude, AI, or automated tools. Amend the commit if there are any lines on the message that contain "Co-Authored-By:" or "Claude-Session:"
6. Commit the groups one at a time, a group that others build on first, each with
   `git commit -m "<message>" -- <every path in the group>`. Naming the paths commits only those,
   and the other groups stay staged for their own commits. Finish with `git status --short`:
   nothing that was staged after step 3 should be left over. If anything is, commit it with the
   group it belongs to (`git commit --amend --no-edit -- <paths>` if that was the last commit,
   otherwise as one more commit).
7. If the repository has a `CHANGELOG.md` whose entries are headed `## [<hash>] - <date>` (see
   "Latest CHANGELOG entry" above), record the commits in it as one separate commit. A commit
   cannot contain its own hash (amending changes it), so never amend for this. Skip a commit that
   only touched `CHANGELOG.md`, `README.md` or `AGENTS.md`, and skip this step when every commit
   is skipped.
   - Get the hashes and dates with `git log -<number of commits made> --format='%h %ad' --date=short`.
   - `Read` the top of `CHANGELOG.md`, then `Edit` one new entry per commit above the latest one,
     newest first, matching the existing format: `## [<hash>] - <date>`, then `### Added` /
     `### Changed` / `### Fixed` sections with one bullet per user-visible change, written from
     that commit's diff.
   - Run `git add CHANGELOG.md` and `git commit -m "Update changelog"`.

Only make tool calls. Do not output any text — the one exception is the `AskUserQuestion` call when
the scan flags something.
