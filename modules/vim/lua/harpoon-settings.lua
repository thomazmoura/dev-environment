require("harpoon").setup()

-- Keybindings for harpoon
local opts = { noremap = true, silent = true }
-- Quick Menu
vim.keymap.set('n', '<Leader>h<Leader>', require("harpoon.ui").toggle_quick_menu, opts)

-- Default bindings to read main indexes
vim.keymap.set('n', '<Leader>hj', '<cmd>lua require("harpoon.ui").nav_file(1)<Enter>', opts)
vim.keymap.set('n', '<Leader>hk', '<cmd>lua require("harpoon.ui").nav_file(2)<Enter>', opts)
vim.keymap.set('n', '<Leader>hl', '<cmd>lua require("harpoon.ui").nav_file(3)<Enter>', opts)
vim.keymap.set('n', '<Leader>h;', '<cmd>lua require("harpoon.ui").nav_file(4)<Enter>', opts)
vim.keymap.set('n', '<Leader>hu', '<cmd>lua require("harpoon.ui").nav_file(5)<Enter>', opts)
vim.keymap.set('n', '<Leader>hi', '<cmd>lua require("harpoon.ui").nav_file(6)<Enter>', opts)
vim.keymap.set('n', '<Leader>ho', '<cmd>lua require("harpoon.ui").nav_file(7)<Enter>', opts)
vim.keymap.set('n', '<Leader>hp', '<cmd>lua require("harpoon.ui").nav_file(8)<Enter>', opts)

-- Default bindings to set main indexes
vim.keymap.set('n', '<Leader>hJ', '<cmd>lua require("harpoon.mark").set_current_at(1)<Enter>', opts)
vim.keymap.set('n', '<Leader>hK', '<cmd>lua require("harpoon.mark").set_current_at(2)<Enter>', opts)
vim.keymap.set('n', '<Leader>hL', '<cmd>lua require("harpoon.mark").set_current_at(3)<Enter>', opts)
vim.keymap.set('n', '<Leader>h:', '<cmd>lua require("harpoon.mark").set_current_at(4)<Enter>', opts)
vim.keymap.set('n', '<Leader>hU', '<cmd>lua require("harpoon.mark").set_current_at(5)<Enter>', opts)
vim.keymap.set('n', '<Leader>hI', '<cmd>lua require("harpoon.mark").set_current_at(6)<Enter>', opts)
vim.keymap.set('n', '<Leader>hO', '<cmd>lua require("harpoon.mark").set_current_at(7)<Enter>', opts)
vim.keymap.set('n', '<Leader>hP', '<cmd>lua require("harpoon.mark").set_current_at(8)<Enter>', opts)

-- Single key bindings using alt for the 4 main indexes
vim.keymap.set('n', '<M-j>', '<cmd>lua require("harpoon.ui").nav_file(1)<Enter>', opts)
vim.keymap.set('n', '<M-k>', '<cmd>lua require("harpoon.ui").nav_file(2)<Enter>', opts)
vim.keymap.set('n', '<M-l>', '<cmd>lua require("harpoon.ui").nav_file(3)<Enter>', opts)
vim.keymap.set('n', '<M-;>', '<cmd>lua require("harpoon.ui").nav_file(4)<Enter>', opts)
vim.keymap.set('n', '<M-S-j>', '<cmd>lua require("harpoon.mark").set_current_at(1)<Enter>', opts)
vim.keymap.set('n', '<M-S-k>', '<cmd>lua require("harpoon.mark").set_current_at(2)<Enter>', opts)
vim.keymap.set('n', '<M-S-l>', '<cmd>lua require("harpoon.mark").set_current_at(3)<Enter>', opts)
vim.keymap.set('n', '<M-:>', '<cmd>lua require("harpoon.mark").set_current_at(4)<Enter>', opts)

-- Additional keybindings
vim.keymap.set('n', '<Leader>hm', require("harpoon.mark").add_file, opts)
vim.keymap.set('n', '<Leader>hd', require("harpoon.mark").clear_all, opts)
vim.keymap.set('n', '<Leader>hn', require("harpoon.ui").nav_next, opts)
vim.keymap.set('n', '<Leader>hN', require("harpoon.ui").nav_next, opts)
vim.keymap.set('n', '<Leader>hN', require("harpoon.ui").nav_next, opts)
