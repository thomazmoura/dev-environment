-- Plain-Vim keymaps, shared by the terminal NeoVim and the VS Code profile
-- (which overrides a few of them with VS Code actions)
local map = vim.keymap.set

-- Buffers
map('n', '<Leader><Tab>', '<cmd>b#<cr>', { desc = 'Alternate buffer' })
map('n', 'gb', '<cmd>bnext<cr>', { desc = 'Next buffer' })
map('n', 'gB', '<cmd>bprevious<cr>', { desc = 'Previous buffer' })
map('n', '<Leader>bd', '<cmd>bd<cr>', { desc = 'Delete buffer' })
map('n', '<Leader>bD', '<cmd>bd#<cr>', { desc = 'Delete alternate buffer' })

-- Quickfix list
map('n', '<Leader>]', '<cmd>cnext<cr>', { desc = 'Next quickfix item' })
map('n', '<Leader>[', '<cmd>cprevious<cr>', { desc = 'Previous quickfix item' })

-- Save
map('n', '<Leader><Leader>', '<cmd>w<cr>', { desc = 'Save' })

-- The current file's path to the clipboard
map('n', '<Leader>%', function() vim.fn.setreg('+', vim.fn.expand('%')) end, { desc = 'Copy file path' })

-- Swap the selection with the last deleted text
map('x', 'gs', 'p2g;P', { desc = 'Swap with deleted text' })

-- Delete the previous word
map({ 'i', 'c' }, '<C-BS>', '<C-w>')
map({ 'i', 'c' }, '<C-h>', '<C-w>')

-- Browsable command line history
map('n', '<Leader>:', 'q:i', { desc = 'Command history' })

-- Insert a GUID/UUID after / before the cursor
map('n', '<Leader>gg', 'mz<cmd>r!uuidgen<cr>y$dd`z"0p', { desc = 'Insert GUID' })
map('n', '<Leader>gG', 'mz<cmd>r!uuidgen<cr>y$dd`z"0P', { desc = 'Insert GUID before' })

-- <Leader> for "+ (system clipboard), <Leader>0 for "0 (last yank)
map('', '<Leader>y', '"+y', { desc = 'Yank to clipboard' })
map('', '<Leader>Y', '"+Y', { desc = 'Yank line to clipboard' })
map('', '<Leader>p', '"+p', { desc = 'Paste from clipboard' })
map('', '<Leader>P', '"+P', { desc = 'Paste from clipboard before' })
map('', '<Leader>0p', '"0p', { desc = 'Paste last yank' })
map('', '<Leader>0P', '"0P', { desc = 'Paste last yank before' })
map('', '<Leader>0d', '"0d', { desc = 'Delete into yank register' })

-- Splits and lines
map('n', '<Leader>\\', '<cmd>vsplit<cr>', { desc = 'Vertical split' })
map('n', '<Leader><CR>', 'i<CR><Esc>', { desc = 'Break the line' })

-- Sort the selection, removing duplicates
map('x', '<Leader>s', ":'<,'>sort u<CR>", { silent = true, desc = 'Sort unique' })

-- Arrows scroll
map('', '<Down>', '<C-e>')
map('', '<Up>', '<C-y>')

-- U redoes
map('n', 'U', '<C-r>', { desc = 'Redo' })

map('n', '<Leader>L', '<cmd>set relativenumber!<cr>', { desc = 'Toggle relative numbers' })
