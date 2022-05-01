--impatient.nvim (for caching purposes)
require('impatient')

--require custom modules
package.path = package.path .. ";" .. vim.env.HOME .. "/.vim/lua/?.lua"
require('icons')

--lualine settings
require('lualine').setup {
  options = {
    icons_enabled = false,
    theme = 'auto',
    component_separators = { left = '', right = ''},
    section_separators = { left = '', right = ''},
    disabled_filetypes = {},
    always_divide_middle = false,
    globalstatus = true,
  },
  sections = {
    lualine_a = {'mode'},
    lualine_b = {
      {
       'diagnostics' 
      },
      {
        'filename',
        path = 1,
      }
    },
    lualine_c = {},
    lualine_x = {'vim.b.coc_git_blame'},
    lualine_y = {'progress', 'filetype', 'encoding'},
    lualine_z = {'location'}
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {'filename'},
    lualine_x = {'location'},
    lualine_y = {},
    lualine_z = {}
  },
  tabline = {
    lualine_a = {
      'buffers'
    }
  },
  extensions = {}
}

-- NeoVim TreeSitter configurationsetup
package.path = package.path .. ";" .. vim.env.HOME .. "/.modules/neovim-treesitter/treesitter-config.lua"
require'treesitter-setup'

-- nvim-tree setup
require'nvim-tree'.setup {
  update_focused_file = {
    enable = true,
    update_cwd = false,
    ignore_list = {},
  },
  diagnostics = {
    enable = true,
    show_on_dirs = true,
  },
}

require'hop'.setup()

vim.api.nvim_set_keymap('', 'gj', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = true })<cr>", {})
vim.api.nvim_set_keymap('n', 'gj', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = false })<cr>", {})
vim.api.nvim_set_keymap('', 'gJ', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = false })<cr>", {})
