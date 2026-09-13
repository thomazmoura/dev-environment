-- copilot
require('copilot').setup({
  copilot_node_command = os.getenv('HOME') .. '/.nvs/copilot-node',
  suggestion = {
    enabled = true,
    auto_trigger = true,
    hide_during_completion = false,
    debounce = 75,
    keymap = {
      accept = "<End>",
      accept_word = "<M-l>",
      accept_line = "<M-j>",
      next = "<M-.>",
      prev = "<M-,>",
      dismiss = "<C-]>",
    },
  },
})

require("claudecode").setup({
  terminal = {
    cwd = vim.fn.expand("~/.local/bin/claude"),
  },
})

-- Claude Code keybindings
vim.keymap.set('n', '<leader>ac', '<cmd>ClaudeCode<cr>', { desc = "Toggle Claude" })
vim.keymap.set('n', '<leader>af', '<cmd>ClaudeCodeFocus<cr>', { desc = "Focus Claude" })
vim.keymap.set('n', '<leader>ar', '<cmd>ClaudeCode --resume<cr>', { desc = "Resume Claude" })
vim.keymap.set('n', '<leader>aC', '<cmd>ClaudeCode --continue<cr>', { desc = "Continue Claude" })
vim.keymap.set('n', '<leader>am', '<cmd>ClaudeCodeSelectModel<cr>', { desc = "Select Claude model" })
vim.keymap.set('n', '<leader>ab', '<cmd>ClaudeCodeAdd %<cr>', { desc = "Add current buffer" })
vim.keymap.set('v', '<leader>as', '<cmd>ClaudeCodeSend<cr>', { desc = "Send to Claude" })
vim.keymap.set('n', '<leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', { desc = "Accept diff" })
vim.keymap.set('n', '<leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', { desc = "Deny diff" })

-- Tmux navigation from within the terminal
-- Wrapped in VimEnter to override vim-tmux-navigator's tnoremap <expr> mappings,
-- which use <C-w>: and don't work correctly in the Claude Code terminal.
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    local nav_from_terminal = function(cmd)
      return function()
        vim.b.restore_terminal_mode = true
        vim.cmd(cmd)
      end
    end

    vim.keymap.set('t', '<C-h>', nav_from_terminal('TmuxNavigateLeft'), { desc = "Tmux navigation left from the terminal" })
    vim.keymap.set('t', '<C-j>', nav_from_terminal('TmuxNavigateDown'), { desc = "Tmux navigation down from the terminal" })
    vim.keymap.set('t', '<C-k>', nav_from_terminal('TmuxNavigateUp'), { desc = "Tmux navigation up from the terminal" })
    vim.keymap.set('t', '<C-l>', nav_from_terminal('TmuxNavigateRight'), { desc = "Tmux navigation right from the terminal" })
    vim.keymap.set('t', '<C-Space>', '<C-\\><C-n>', { desc = "Switch to normal mode" })
  end,
})

-- Tmux navigation from an nvim on the other end of an ssh. The tmux there is
-- not ours: $TMUX is unset, so vim-tmux-navigator only moves between windows,
-- and the local tmux sees nothing but ssh on the pane's tty. So nvim puts in
-- its title the ways it still has a window to go -- nvim-nav=hl at the left
-- edge of a vertical split -- and the local C-h/j/k/l bindings read that from
-- #{pane_title} (modules/tmux/common.conf): a key comes here when its letter
-- is there and moves the tmux pane when it is not.
--
-- Through 'title', rather than writing the escape by hand, because nvim then
-- gives the title back when it exits or is suspended, and the shell left in
-- the pane gets its keys again.
--
-- The same title carries SpotlightDimmer's focused split (sd-nvim=..., from
-- the spotlight-dimmer plugin, set up with manage_title = false in
-- setup.lua), so the desktop dims the other splits. It goes AFTER the ways:
-- the bindings match nvim-nav=*h* against the whole title from its start, and
-- the segment holds no h/j/k/l to be mistaken for a way.
if vim.env.SSH_TTY and not vim.env.TMUX then
  local ways = ''
  local set_navigation_title = function()
    -- A float has no neighbours: keep the ways the window under it had.
    if vim.api.nvim_win_get_config(0).relative == '' then
      ways = ''
      for _, way in ipairs({ 'h', 'j', 'k', 'l' }) do
        if vim.fn.winnr(way) ~= vim.fn.winnr() then
          ways = ways .. way
        end
      end
    end
    -- Empty on a float, which spotlights the whole pane
    local ok, spotlight_dimmer = pcall(require, 'spotlight-dimmer')
    local split = ok and spotlight_dimmer.title_segment() or ''
    vim.o.titlestring = 'nvim-nav=' .. ways .. (split ~= '' and ' ' .. split or '')
  end

  vim.o.title = true
  set_navigation_title()
  -- WinClosed fires while the window is still there: look once it is gone.
  -- BufWinEnter: a winbar can come or go with the buffer, moving the split.
  vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'WinClosed', 'WinResized', 'VimResized', 'TabEnter', 'BufWinEnter' }, {
    callback = function() vim.schedule(set_navigation_title) end,
  })
end

-- Restore terminal mode when returning to a terminal buffer that was left
-- via Ctrl+hjkl navigation. Does not affect terminals exited intentionally
-- with <C-\><C-n>.
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function()
    if vim.bo.buftype == 'terminal' and vim.b.restore_terminal_mode then
      vim.b.restore_terminal_mode = false
      vim.cmd('startinsert')
    end
  end,
})

