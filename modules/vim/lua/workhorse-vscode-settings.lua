local vscode = require('vscode')
local default_global_options = { noremap = true, silent = true }

-- Query shortcuts - call VS Code extension with specific GUID
vim.keymap.set('n', '<leader>wT', function()
  vscode.call('workhorse.openQuery', { args = { '0ce03ce4-34b3-417b-a7d7-928d45a970dc' } })
end, default_global_options) -- Tree (caps)

vim.keymap.set('n', '<leader>wt', function()
  vscode.call('workhorse.openQuery', { args = { 'a7977848-adab-4453-a4cf-39c28163ac3c' } })
end, default_global_options) -- Tree

vim.keymap.set('n', '<leader>wu', function()
  vscode.call('workhorse.openQuery', { args = { '729b31ef-3bce-4fcb-b300-0342e4ce69c8' } })
end, default_global_options) -- User Stories

vim.keymap.set('n', '<leader>wf', function()
  vscode.call('workhorse.openQuery', { args = { '38cfedab-c989-41bb-9d28-71d2c4ad9464' } })
end, default_global_options) -- Feature

vim.keymap.set('n', '<leader>we', function()
  vscode.call('workhorse.openQuery', { args = { '7c0761cd-ba78-4769-a28e-68685934d0aa' } })
end, default_global_options) -- Epic

vim.keymap.set('n', '<leader>wl', function()
  vscode.call('workhorse.openQuery', { args = { 'd53e77f7-d7c8-49ff-ba14-35a061d047e9' } })
end, default_global_options) -- LuaLine

vim.keymap.set('n', '<leader>wa', function()
  vscode.call('workhorse.openQuery', { args = { '3c82101c-2a67-408f-9fd7-8ad00a55710c' } })
end, default_global_options) -- Full (All)

vim.keymap.set('n', '<leader>wx', function()
  vscode.call('workhorse.openQuery', { args = { '9a90e30d-0827-4fe9-9426-e70a8fd62ca6' } })
end, default_global_options) -- Trash

-- General workhorse commands (equivalents from keybinding-settings.lua)
vim.keymap.set('n', '<leader>wq', function()
  vscode.call('workhorse.pickQuery')
end, default_global_options) -- Pick query

vim.keymap.set('n', '<leader>wr', function()
  vscode.call('workhorse.refresh')
end, default_global_options) -- Refresh

-- Additional VS Code extension commands
vim.keymap.set('n', '<leader>ws', function()
  vscode.call('workhorse.changeState')
end, default_global_options) -- Change state

vim.keymap.set('n', '<leader>wR', function()
  vscode.call('workhorse.resume')
end, default_global_options) -- Resume last query

vim.keymap.set('n', '<leader>wi', function()
  vscode.call('workhorse.openInBrowser')
end, default_global_options) -- Open in browser

vim.keymap.set('n', '<leader>wD', function()
  vscode.call('workhorse.openDescription')
end, default_global_options) -- Open description
