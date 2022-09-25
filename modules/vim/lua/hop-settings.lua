-- hop
require'hop'.setup()

vim.api.nvim_set_keymap('', 'gj', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = true })<cr>", {})
vim.api.nvim_set_keymap('n', 'gj', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = false })<cr>", {})
vim.api.nvim_set_keymap('', 'gJ', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = false })<cr>", {})
vim.api.nvim_set_keymap('n', '<leader>j', "<cmd>HopLineStartAC<cr>", {})
vim.api.nvim_set_keymap('n', '<leader>k', "<cmd>HopLineStartBC<cr>", {})

