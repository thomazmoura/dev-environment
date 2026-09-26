return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      copilot_node_command = vim.env.HOME .. '/.nvs/copilot-node',
      suggestion = {
        enabled = true,
        auto_trigger = true,
        hide_during_completion = false,
        debounce = 75,
        keymap = {
          accept = '<End>',
          accept_word = '<M-l>',
          accept_line = '<M-j>',
          next = '<M-.>',
          prev = '<M-,>',
          dismiss = '<C-]>',
        },
      },
    },
  },

  {
    'coder/claudecode.nvim',
    -- Not lazy: it runs the IDE server a `claude` in another pane connects to
    lazy = false,
    keys = {
      { '<Leader>ac', '<cmd>ClaudeCode<cr>', desc = 'Toggle Claude' },
      { '<Leader>af', '<cmd>ClaudeCodeFocus<cr>', desc = 'Focus Claude' },
      { '<Leader>ar', '<cmd>ClaudeCode --resume<cr>', desc = 'Resume Claude' },
      { '<Leader>aC', '<cmd>ClaudeCode --continue<cr>', desc = 'Continue Claude' },
      { '<Leader>am', '<cmd>ClaudeCodeSelectModel<cr>', desc = 'Select Claude model' },
      { '<Leader>ab', '<cmd>ClaudeCodeAdd %<cr>', desc = 'Add current buffer' },
      { '<Leader>as', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = 'Send to Claude' },
      { '<Leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', desc = 'Accept diff' },
      { '<Leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', desc = 'Deny diff' },
    },
    opts = {
      terminal_cmd = vim.env.HOME .. '/.local/bin/claude',
    },
  },
}
