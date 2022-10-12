--require custom modules
package.path = package.path .. ";" .. vim.env.HOME .. "/.vim/lua/?.lua"

-- Import custom sub-settings
require('hop-settings')
require('icons-settings')
require('lsp-settings')
require('lualine-settings')
require('telescope-settings')
require('treesitter-settings')

require('neoscroll').setup {
  mappings = {'<C-u>', '<C-d>', '<C-y>', 'zt', 'zz', 'zb'},
  easing_function = "cubic"
}

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

-- auto-save
require("auto-save").setup {
  enabled = true,
  trigger_events = { "BufLeave" },
}

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

require("nvim-autopairs").setup()

-- If you want insert `(` after select function or method item
local cmp_autopairs = require('nvim-autopairs.completion.cmp')
local cmp = require('cmp')
if cmp ~= nil then
  cmp.event:on(
    'confirm_done',
    cmp_autopairs.on_confirm_done()
  )
end

