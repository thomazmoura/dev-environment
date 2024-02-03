-- Util
local home_directory = vim.fn.expand("$HOME");

-- DAP configuration
local dap, dapui = require("dap"), require("dapui")

dap.adapters.coreclr = {
  type = 'executable',
  command = home_directory .. '/.local/bin/netcoredbg',
  args = { '--interpreter=vscode' }
}

dap.configurations.cs = {
  {
    type = "coreclr",
    name = "launch - netcoredbg",
    request = "launch",
    cwd = function()
      return vim.fn.input('Path to csproj: ', vim.fn.getcwd(), 'dir')
    end,
    program = function()
      return vim.fn.input('Path to dll: ', vim.fn.getcwd(), 'file')
    end,
  },
}

require('nvim-dap-virtual-text').setup()

-- DAP UI configuration
dapui.setup()
dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
  dapui.close()
end

-- Keybindings
vim.keymap.set('n', '<Leader>dr', dap.continue)
vim.keymap.set('n', '<Leader>dh', dap.continue)
vim.keymap.set('n', '<Leader>dl', dap.step_over)
vim.keymap.set('n', '<Leader>dk', dap.step_out)
vim.keymap.set('n', '<Leader>dj', dap.step_into)
vim.keymap.set('n', '<Leader>dd', dap.toggle_breakpoint)
vim.keymap.set('n', '<Leader>dD', "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>")
vim.keymap.set('n', '<Leader>do', dap.repl.open)
vim.keymap.set('n', '<Leader>dR', dap.run_last)
vim.keymap.set('n', '<Leader>ds', dap.close)

