---
name: commit
description: Stage and commit pending changes with an auto-generated message
model: haiku
disable-model-invocation: true
allowed-tools: Bash(git add *) Bash(git status *) Bash(git diff *) Bash(git commit *) Bash(git log *)
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Based on the above changes, create a single git commit:

1. Stage all modified tracked files using `git add`
2. Write a concise commit message:
   - Imperative mood (e.g., "Add feature", "Fix bug", "Update config")
   - First line under 72 characters
   - **IMPORTANT!** No reference to Claude, AI, or automated tools
3. Run `git commit -m "<message>"`

Only make tool calls. Do not output any text.
