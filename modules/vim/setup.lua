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

