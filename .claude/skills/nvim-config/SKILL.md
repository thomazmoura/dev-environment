---
name: nvim-config
description: How this repo's NeoVim config is laid out - Lua with lazy.nvim, one spec file per domain, the Notes pane profile, the VS Code profile, and personal plugins (workhorse.nvim, paperboy.nvim).
when_to_use: Use when asked to add or change a NeoVim plugin, keymap, option, autocmd, LSP/completion/telescope setup, the Notes pane's NeoVim, the vscode-neovim profile, or Workhorse/Paperboy in NeoVim, or when editing anything in modules/nvim-config, modules/vim or modules/neovim-lsp.
---

# NeoVim configuration

`~/.config/nvim` → `modules/nvim-config/`. Edits take effect in the next NeoVim started.

## Layout

| Path | What lives there |
|---|---|
| `init.lua` | Entry point. Sets the leader (Space), requires `config.*`, then lazy |
| `lua/config/` | Options, filetypes, commands, autocmds, `keymaps/` (`common.lua` is shared with VS Code), clipboard (OSC 52 over ssh), `cmdline_normal.lua` (normal mode in the command line), `pane_background.lua` and `ssh_title.lua` (tmux integration) |
| `lua/config/lazy.lua` | lazy.nvim setup. `defaults.cond = not vim.g.vscode`. `dev.path = ~/code` for `thomazmoura/*` plugins (falls back to GitHub) |
| `lua/plugins/<domain>.lua` | One file per domain: `ai`, `colorscheme`, `completion`, `database`, `debug`, `editor`, `git`, `lsp`, `personal`, `telescope`, `tmux`, `treesitter`, `ui` |
| `lazy-lock.json` | Pinned versions. Commit it after `:Lazy update`/`sync`. Setup runs `Lazy! restore` |
| `after/ftplugin/`, `snippets/` | Per-filetype tweaks, VS Code-format snippets |
| `lua/vscode-profile/` | Keymaps/commands used instead of plugins when `vim.g.vscode` |
| `notes.lua` | The **Notes pane** profile (`nvim -u ~/.config/nvim/notes.lua`, tmux `prefix,n`) |

`modules/vim/` holds data only (spell files, swap), behind `~/.local/share/nvim/site`. It has no config.

## Conventions

- **A plugin's keymaps go in its spec's `keys`**, and its setup in `opts`/`config`, inside the matching domain file. General keymaps go in `lua/config/keymaps/`.
- **A spec loads under VS Code only with `cond = true`.**
- **The Notes pane is deliberately minimal:** `loadplugins = false`, and it adds only vim-tmux-navigator, auto-save.nvim and markview.nvim from the full config's lazy install via its `add()`. It has no status bar, a transparent background, and treats `.notes` as markdown. Changes asked "for the Notes pane" go in `notes.lua`, not the full config.
- **Personal plugins** are in `lua/plugins/personal.lua`: workhorse.nvim (Azure DevOps), paperboy.nvim (Exchange inbox), spotlight-dimmer. They load from `~/code/<plugin>` when present, so changes to the plugin itself belong in that repo. Paperboy loads only when `$PAPERBOY_EWS_URL` is set.
- **LSP servers** are configured in `lua/plugins/lsp.lua` (`vim.lsp.enable`, `node_server(...)` for npm ones). Installers are in `modules/neovim-lsp/`; the `deploy` skill has the recipe.
- **NeoVim usually runs through pwsh** (tmux panes use `pwsh_invocation`) so the profile's environment and `Use-NodeVersion` apply. Copilot and node-based servers rely on that.

## Verifying

```bash
nvim --headless "+qa"                                         # full config loads without errors
nvim --headless -u modules/nvim-config/notes.lua "+qa"        # Notes profile
nvim --headless "+Lazy! restore" +qa                          # after editing lazy-lock.json
```
