if not (vim.g.vscode) and not (vim.g.azuredatastudio) then
  --require custom modules
  package.path = package.path .. ";" .. vim.env.HOME .. "/.vim/lua/?.lua"

  -- Vim settings
  vim.wo.signcolumn = "yes:1"

  -- Import custom sub-settings
  require('hop-settings')
  require('icons-settings')
  require('lsp-settings')
  require('lualine-settings')
  require('telescope-settings')
  require('treesitter-settings')
  require('gitsigns-settings')
  require('harpoon-settings')
  require('debug-settings')
  require('noice-settings')

  -- neo-scroll
  require('neoscroll').setup {
    mappings = { '<C-u>', '<C-d>', '<C-y>', 'zt', 'zz', 'zb' },
    easing_function = "cubic"
  }

  -- nvim-tree setup
  require 'nvim-tree'.setup {
    update_focused_file = {
      enable = true,
      update_cwd = false,
      ignore_list = {},
    },
    -- currently disabled due to performance issues
    diagnostics = {
      enable = false,
      show_on_dirs = false,
    },
    view = {
      width = 50,
    }
  }

  -- auto-save
  require("auto-save").setup {
    enabled = true,
    trigger_events = { "BufLeave" },
  }

  -- nvim-autopairs
  require("nvim-autopairs").setup()
  local cmp_autopairs = require('nvim-autopairs.completion.cmp')
  local cmp = require('cmp')
  if cmp ~= nil then
    cmp.event:on(
      'confirm_done',
      cmp_autopairs.on_confirm_done()
    )
  end

  -- codewindow (minimap)
  require('codewindow').setup()
  local opts = { noremap = true, silent = true }
  vim.keymap.set('n', '<Leader>mm', require('codewindow').open_minimap, opts)
  vim.keymap.set('n', '<Leader>mc', require('codewindow').close_minimap, opts)
  vim.keymap.set('n', '<Leader>mf', require('codewindow').toggle_focus, opts)

  -- tint (fade inactive windows)
  require("tint").setup({
    tint = -75,
    tint_background_colors = false
  })

  if os.getenv('WSLENV') then
    vim.g.clipboard = {
      name = 'win32yank-wsl',
      copy = {
        ['+'] = 'win32yank.exe -i --crlf',
        ['*'] = 'win32yank.exe -i --crlf',
      },
      paste = {
        ['+'] = 'win32yank.exe -o --lf',
        ['*'] = 'win32yank.exe -o --lf',
      },
      cache_enabled = 0,
    }
  else
    require("tmux").setup({
      copy_sync = {
        sync_clipboard = true,
        sync_registers = false,
      }
    })
  end

  vim.o.timeout = true
  vim.o.timeoutlen = 1000
  require("which-key").setup({
    window = {
      winblend = 15
    },
  })
end
