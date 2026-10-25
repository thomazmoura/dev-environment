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
| `lua/config/` | Options, filetypes, commands, autocmds, `keymaps/` (`common.lua` is shared with VS Code), clipboard (OSC 52 over ssh), `paste_image.lua` (`<Leader>p` in markdown buffers pastes a clipboard image as a saved file plus a Markdown image link), `cmdline_normal.lua` (normal mode in the command line), `pane_background.lua` and `ssh_title.lua` (tmux integration), `sqlserver_locksmith.lua` (dadbod's SQL Server passwords), `dbout_compact.lua` (lays out SQL Server results from sqlcmd's separator-split output: line breaks as ↵, long values cut on screen, `yic` yanking the whole value via `after/ftplugin/dbout.lua`), `sql_dialect.lua` (which SQL language server a sql buffer gets), `sql_connection.lua` (connects SqlToolsService to the buffer's dadbod database with `connection/connect`, so hover shows column types and `gd` opens a table's or view's CREATE script, which inherits the connection), `sql_statement.lua` (`<Leader>r` in a sql buffer runs only the statement under the cursor, `<Leader>R` the buffer; the statement comes from `sql_split_sqlserver.lua`, a client of `sql_split_sqlserver.ps1`, a long-running pwsh that parses with SqlToolsService's ScriptDom and caches its compiled C# in `~/.cache/nvim/sql_split_sqlserver/`, or from `sql_split_postgres.lua`, psql's own `;` rules in Lua), `sql_star.lua` (`gd` on a SELECT's `*` replaces it with its columns, qualified by the table's alias, or its name through a join: the FROM from the same pwsh ScriptDom service, the columns from `sys.dm_exec_describe_first_result_set` over the dadbod connection), `sql_join.lua` (blink's source completing a join's ON with the conditions of the real foreign keys between the joined table and the ones before it, first in the list: the tables from the same pwsh ScriptDom service, which parses the unfinished ON with a placeholder condition, the keys from `sys.foreign_keys`, read once per connection; a space opens the menu only after an ON), `bare_path.lua` (blink's path source, completing paths without a leading `./`), `dadbod_fuzzy.lua` (blink's dadbod source, handing blink every table/column for the context so it filters fuzzily instead of by prefix) |
| `autoload/sqlserver_locksmith.vim` | vim-dadbod's sqlserver adapter (`g:db_adapter_sqlserver` points to it): dadbod's own, with the password filled in by `config/sqlserver_locksmith.lua` |
| `lua/config/lazy.lua` | lazy.nvim setup. `defaults.cond = not vim.g.vscode`. `dev.path = ~/code` for `thomazmoura/*` plugins (falls back to GitHub) |
| `lua/plugins/<domain>.lua` | One file per domain: `ai`, `colorscheme`, `completion`, `database`, `debug`, `editor`, `git`, `lsp`, `paperboy`, `personal`, `telescope`, `tmux`, `treesitter`, `ui` |
| `lazy-lock.json` | Pinned versions. Commit it after `:Lazy update`/`sync`. Setup runs `Lazy! restore` |
| `after/ftplugin/`, `snippets/` | Per-filetype tweaks, VS Code-format snippets |
| `lua/vscode-profile/` | Keymaps/commands used instead of plugins when `vim.g.vscode` |
| `notes.lua` | The **Notes pane** profile (`nvim -u ~/.config/nvim/notes.lua`, tmux `prefix,n`) |

`modules/vim/` holds data only (spell files, swap), behind `~/.local/share/nvim/site`. It has no config.

## Conventions

- **A plugin's keymaps go in its spec's `keys`**, and its setup in `opts`/`config`, inside the matching domain file. General keymaps go in `lua/config/keymaps/`.
- **A spec loads under VS Code only with `cond = true`.**
- **The Notes pane is deliberately minimal:** `loadplugins = false`, and it adds only vim-tmux-navigator, auto-save.nvim and markview.nvim from the full config's lazy install via its `add()`. It has no status bar, a transparent background, and treats `.notes` as markdown. Changes asked "for the Notes pane" go in `notes.lua`, not the full config.
- **Personal plugins** are in `lua/plugins/personal.lua` (workhorse.nvim for Azure DevOps, spotlight-dimmer) and `lua/plugins/paperboy.lua` (paperboy.nvim, the Exchange inbox, with its e-mail signature in `compose.signature_file`). They load from `~/code/<plugin>` when present, so changes to the plugin itself belong in that repo. Paperboy loads only when `$PAPERBOY_EWS_URL` is set. Both keep their secrets (PAT, Exchange password, cache keys) in **locksmith.nvim** (`~/code/locksmith.nvim`), one encrypted store unlocked with a password asked once per NeoVim (`:Locksmith`, `bin/locksmith` on the command line). Dadbod keeps its SQL Server passwords there too (namespace `dadbod`, one per server and login), saved once the server accepted them.
- **LSP servers** are configured in `lua/plugins/lsp.lua` (`vim.lsp.enable`, `node_server(...)` for npm ones). Installers are in `modules/neovim-lsp/`; the `deploy` skill has the recipe. The two SQL servers (`sqlserver_ls`, `postgres_lsp`) share the sql filetype, so they stay out of `vim.lsp.enable`: `config/sql_dialect.lua` starts one per buffer, from a pin (`:SqlDialect`, `<Leader>dm`/`dp`/`da`), the dadbod connection, or the syntax.
- **NeoVim usually runs through pwsh** (tmux panes use `pwsh_invocation`) so the profile's environment and `Use-NodeVersion` apply. Copilot and node-based servers rely on that.

## Verifying

```bash
nvim --headless "+qa"                                         # full config loads without errors
nvim --headless -u modules/nvim-config/notes.lua "+qa"        # Notes profile
nvim --headless "+Lazy! restore" +qa                          # after editing lazy-lock.json
```
