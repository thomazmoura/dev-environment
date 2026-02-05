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

