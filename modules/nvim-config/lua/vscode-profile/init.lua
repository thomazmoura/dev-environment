-- vscode-neovim profile: VS Code draws the editor, so no UI plugins or
-- colours -- just the shared keymaps plus VS Code actions.
-- (Not lua/vscode/: that name belongs to vscode-neovim's own `vscode` module.)

vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('YankHighlight', { clear = true }),
  callback = function() vim.hl.on_yank({ higroup = 'IncSearch', timeout = 450 }) end,
})

require('config.keymaps.common')
require('vscode-profile.keymaps')
require('vscode-profile.workhorse')
require('vscode-profile.sql')
