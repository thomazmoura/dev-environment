return {
  {
    'christoomey/vim-tmux-navigator',
    lazy = false,
    init = function()
      -- Write all buffers before moving from NeoVim to a tmux pane
      vim.g.tmux_navigator_save_on_switch = 2
    end,
    config = function()
      -- The plugin's own terminal-mode maps go through <C-w>:, which the
      -- Claude Code terminal swallows. These leave terminal mode first and
      -- flag the buffer so that coming back resumes it (config/autocmds.lua).
      local function from_terminal(command)
        return function()
          vim.b.restore_terminal_mode = true
          vim.cmd(command)
        end
      end
      vim.keymap.set('t', '<C-h>', from_terminal('TmuxNavigateLeft'), { desc = 'Navigate left' })
      vim.keymap.set('t', '<C-j>', from_terminal('TmuxNavigateDown'), { desc = 'Navigate down' })
      vim.keymap.set('t', '<C-k>', from_terminal('TmuxNavigateUp'), { desc = 'Navigate up' })
      vim.keymap.set('t', '<C-l>', from_terminal('TmuxNavigateRight'), { desc = 'Navigate right' })
      vim.keymap.set('t', '<C-Space>', '<C-\\><C-n>', { desc = 'Normal mode' })
    end,
  },

  -- tmux buffers <-> registers. Also on an ssh remote's tmux; WSL never used it.
  {
    'aserowy/tmux.nvim',
    cond = vim.env.TMUX ~= nil and vim.env.WSLENV == nil and not vim.g.vscode,
    event = 'VeryLazy',
    opts = {
      copy_sync = {
        enable = true,
        -- Keep the autodetected wl-copy provider for +, so text copied outside
        -- tmux (browsers and such) is still reachable through "+p
        sync_clipboard = false,
        sync_registers = true,
        -- Writing the unnamed register also writes register 0, so syncing it
        -- would clobber the last yank
        sync_unnamed = false,
        -- tmux buffers land on registers 2 to 9, leaving 0 and 1 alone
        register_offset = 2,
      },
      navigation = { enable_default_keybindings = false },
      resize = { enable_default_keybindings = false },
    },
  },
}
