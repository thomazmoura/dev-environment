-- avante
--require('avante_lib').load()
--require('avante').setup({
  --behaviour = {
    --auto_suggestions = false,
  --},
  --file_selector = {
    --provider = 'telescope'
  --},
  --windows = {
    --width = 50
  --}
--})
--require("markview").setup({
  --filetypes = { "Avante" },
  --buf_ignore = {},
  --max_length = 99999,
--})

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

-- sidekick
do
  local ok, sidekick = pcall(require, "sidekick")
  if ok then
    local mux_backend = vim.env.ZELLIJ and "zellij" or "tmux"
    local mux_enabled = vim.env.ZELLIJ ~= nil or vim.env.TMUX ~= nil

    sidekick.setup({
      cli = {
        picker = "telescope",
        mux = {
          backend = mux_backend,
          enabled = mux_enabled,
        },
        tools = {
          claude = { cmd = { "claude" } },
          codex = { cmd = { "codex", "--search" } },
          copilot = { cmd = { "copilot", "--banner" } },
        },
      },
    })

    local cli = require("sidekick.cli")
    local common_opts = { noremap = true, silent = true }
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", common_opts, { desc = desc }))
    end

    map('n', '<leader>aa', function()
      cli.toggle({ focus = true })
    end, 'Sidekick Toggle CLI')

    map('n', '<leader>as', function()
      cli.select()
    end, 'Sidekick Select Tool')

    map('n', '<leader>ad', function()
      cli.close()
    end, 'Sidekick Close Session')

    map({ 'n', 'x' }, '<leader>at', function()
      cli.send({ msg = "{this}" })
    end, 'Sidekick Send Context')

    map('n', '<leader>af', function()
      cli.send({ msg = "{file}" })
    end, 'Sidekick Send File')

    map('x', '<leader>av', function()
      cli.send({ msg = "{selection}" })
    end, 'Sidekick Send Selection')

    map({ 'n', 'x' }, '<leader>ap', function()
      cli.prompt()
    end, 'Sidekick Prompt Library')

    map('n', '<leader>aC', function()
      cli.toggle({ name = "claude", focus = true })
    end, 'Sidekick Toggle Claude')

    map('n', '<leader>ax', function()
      cli.toggle({ name = "codex", focus = true })
    end, 'Sidekick Toggle Codex')

    map('n', '<leader>ao', function()
      cli.toggle({ name = "copilot", focus = true })
    end, 'Sidekick Toggle Copilot CLI')
  end
end

-- copilot chat
require('CopilotChat').setup({
  mappings = {
    complete = {
      insert = '<End>',
    },
    reset = {
      normal = '<C-x>',
      insert = '<C-x>',
    },
  },
})
