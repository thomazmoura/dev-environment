-- NeoVim entry point (~/.config/nvim -> modules/nvim-config).
--
-- The same file serves the terminal NeoVim and the VS Code (vscode-neovim)
-- profile. Both share the options; VS Code then gets its own keymaps and only
-- the few plugins that make sense there (see lua/config/lazy.lua).

vim.loader.enable()

-- Before lazy.nvim, so every plugin's keys see the right leader
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

require('config.options')
require('config.filetypes')
require('config.commands')
require('config.macros')
require('config.lazy')

if vim.g.vscode then
  require('vscode-profile')
else
  require('config.clipboard')
  require('config.keymaps')
  require('config.autocmds')
  require('config.formatting')
  require('config.ssh_title')
  require('config.pane_background')
end
