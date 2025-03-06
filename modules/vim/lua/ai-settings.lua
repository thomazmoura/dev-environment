  -- avante
  require('avante_lib').load()
  require('avante').setup({
    behaviour = {
      auto_suggestions = false,
    },
    file_selector = {
      provider = 'telescope'
    },
    windows = {
      width = 50
    }
  })
  require("markview").setup({
    filetypes = { "Avante" },
    buf_ignore = {},
    max_length = 99999,
  })

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

  -- copilot chat
  require('CopilotChat').setup()


