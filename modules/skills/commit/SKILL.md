---
name: commit
description: Stage and commit pending changes with an auto-generated message
model: haiku
disable-model-invocation: true
allowed-tools: Bash(git add *) Bash(git status *) Bash(git diff *) Bash(git commit *) Bash(git log *) Bash(git restore --staged *) Bash(rg *) AskUserQuestion
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Based on the above changes, create a single git commit:

1. Stage all modified tracked files using `git add -u`
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
   - Also read the added (`+`) lines in the context diff for anything the patterns cannot catch:
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
4. Write a concise commit message:
   - Imperative mood (e.g., "Add feature", "Fix bug", "Update config")
   - First line under 72 characters
   - **IMPORTANT!** No reference to Claude, AI, or automated tools
5. Run `git commit -m "<message>"`

Only make tool calls. Do not output any text — the one exception is the `AskUserQuestion` call when
the scan flags something.
