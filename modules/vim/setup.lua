--require custom modules
package.path = package.path .. ";" .. vim.env.HOME .. "/.vim/lua/?.lua"
require('icons')

require('neoscroll').setup {
  mappings = {'<C-u>', '<C-d>', '<C-y>', 'zt', 'zz', 'zb'},
  easing_function = "cubic"
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

-- Tree Sitter needs gcc or equivalent to work so it's currently only active on Linux
if not vim.env.windir then
  require'nvim-treesitter.configs'.setup {
    -- A list of parser names, or "all" for possible list, check: https://github.com/nvim-treesitter/nvim-treesitter#supported-languages
    ensure_installed = {
      "c",
      "c_sharp",
      "css",
      "dockerfile",
      "html",
      "json",
      "lua",
      "python",
      "regex",
      "rust",
      "typescript",
      "vim",
      "yaml"
    },

    -- Install parsers synchronously (only applied to `ensure_installed`)
    sync_install = false,

    -- List of parsers to ignore installing (for "all")
    ignore_install = { },

    highlight = {
      -- `false` will disable the whole extension
      enable = true,

      -- NOTE: these are the names of the parsers and not the filetype. (for example if you want to disable highlighting for the `tex` filetype, you need to include `latex` in this list as this is the name of the parser)
      -- list of language that will be disabled
      disable = { },

      -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
      -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
      -- Using this option may slow down your editor, and you may see some duplicate highlights.
      -- Instead of true it can also be a list of languages
      additional_vim_regex_highlighting = false,
    },
  }

  require'nvim-treesitter.configs'.setup {
    textobjects = {
      select = {
        enable = true,
        -- Automatically jump forward to textobj, similar to targets.vim
        lookahead = true,
        keymaps = {
          -- You can use the capture groups defined in textobjects.scm
          ["af"] = "@function.outer",
          ["if"] = "@function.inner",
          ["am"] = "@function.outer",
          ["im"] = "@function.inner",
          ["ac"] = "@class.outer",
          ["ic"] = "@class.inner",
          ["ar"] = "@parameter.outer",
          ["ir"] = "@parameter.inner",
          ["ak"] = "@block.outer",
          ["ik"] = "@block.inner",
        },
      },
    },
  }
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

-- hop
require'hop'.setup()

vim.api.nvim_set_keymap('', 'gj', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = true })<cr>", {})
vim.api.nvim_set_keymap('n', 'gj', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = false })<cr>", {})
vim.api.nvim_set_keymap('', 'gJ', "<cmd>lua require'hop'.hint_char1({ inclusive_jump = false })<cr>", {})
vim.api.nvim_set_keymap('n', '<leader>j', "<cmd>HopLineStartAC<cr>", {})
vim.api.nvim_set_keymap('n', '<leader>k', "<cmd>HopLineStartBC<cr>", {})

-- telescope
require('telescope').setup {
  defaults = {
    winblend = 30
  },
  pickers = {
    find_files = {
      find_command = { 'fd', '--type', 'file' }
    },
    buffers = {
      ignore_current_buffer = true,
      sort_lastused = true,
      sort_mru = true,
    }
  },
  extensions = {
    fzf = { }
  }
}

require('telescope').load_extension('fzf')

