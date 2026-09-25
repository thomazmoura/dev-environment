if not (vim.g.vscode) and not (vim.g.azuredatastudio) then
  --require custom modules
  package.path = package.path .. ";" .. vim.env.HOME .. "/.vim/lua/?.lua"

  -- Vim settings
  vim.wo.signcolumn = "yes:1"

  -- Import custom sub-settings
  require('icons-settings')
  require('lsp-settings')
  require('lualine-settings')
  require('telescope-settings')
  require('treesitter-settings')
  require('gitsigns-settings')
  require('harpoon-settings')
  require('debug-settings')
  require('noice-settings')
  require('keybinding-settings')
  require('commands-settings')
  require('scrolling-settings')
  require('hop-settings')
  require('ai-settings')
  require('workhorse-settings')
  require('pane-background')

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
    actions = {
      open_file = {
        window_picker = {
          enable = false,
        },
      },
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

  -- Markview (Markdown rendering on normal mode)
  require("markview").setup({
    buf_ignore = {},
    max_length = 99999,
    markdown = {
      list_items = { shift_width = 2 },
    },
  })


  -- SpotlightDimmer (dim inactive splits via the desktop overlay; no-op
  -- outside tmux/ssh or when the plugin is not installed). Over ssh the
  -- navigation title in ai-settings.lua owns 'titlestring' and appends the
  -- split itself, hence manage_title = false.
  local ok_spotlight_dimmer, spotlight_dimmer = pcall(require, "spotlight-dimmer")
  if ok_spotlight_dimmer then
    spotlight_dimmer.setup({ manage_title = false })
  end

  vim.o.timeout = true
  vim.o.timeoutlen = 1000
  require("which-key").setup()

  -- Clipboard integration
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
  elseif os.getenv('SSH_CONNECTION') and not os.getenv('WAYLAND_DISPLAY') then
    -- Over ssh (prefix+N) "+y goes to the clipboard of the machine you are
    -- ssh'ing from, as an OSC 52 escape the local tmux forwards to the
    -- terminal. SSH_CONNECTION rather than SSH_TTY because tmux's default
    -- update-environment carries it into a tmux started on the remote.
    --
    -- Paste gives back what this NeoVim last copied rather than asking the
    -- terminal for its clipboard, which blocks until it times out when nothing
    -- answers; paste from the local clipboard with the terminal's own paste.
    local osc52 = require('vim.ui.clipboard.osc52')
    local last = {}
    local function copy(reg)
      local send = osc52.copy(reg)
      return function(lines, regtype)
        last[reg] = { lines, regtype }
        send(lines, regtype)
      end
    end
    local function paste(reg)
      return function()
        return last[reg] or { {}, 'v' }
      end
    end
    vim.g.clipboard = {
      name = 'OSC 52',
      copy = { ['+'] = copy('+'), ['*'] = copy('*') },
      paste = { ['+'] = paste('+'), ['*'] = paste('*') },
    }
  end

  -- Separate from the chain above so a tmux on an ssh remote also syncs its
  -- buffers with registers; WSL has never used it
  if os.getenv('TMUX') and not os.getenv('WSLENV') then
    require("tmux").setup({
      copy_sync = {
        -- Without this the whole copy_sync block is inert
        enable = true,
        -- Keep the autodetected wl-copy provider for +, so that text copied
        -- outside of tmux (browsers and such) is still reachable through "+p
        sync_clipboard = false,
        sync_registers = true,
        -- Assigning to the unnamed register also writes through to register 0,
        -- so syncing it would clobber the last yank
        sync_unnamed = false,
        -- Tmux buffers land on registers 2 to 9, leaving 0 and 1 untouched
        register_offset = 2,
      },
      resize = {
        -- enables default keybindings (A-hjkl) for normal mode
        enable_default_keybindings = false,
      }
    })
  end
else
  require('commands-settings')
  require('workhorse-vscode-settings')
end

