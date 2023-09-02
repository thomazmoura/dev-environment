-- DAP configuration
local dap, dapui = require("dap"), require("dapui")

dap.adapters.coreclr = {
  type = 'executable',
  command = '/home/developer/.local/bin/netcoredbg',
  args = {'--interpreter=vscode'}
}

dap.configurations.cs = {
  {
    type = "coreclr",
    name = "launch - netcoredbg",
    request = "launch",
    program = function()
        return vim.fn.input('Path to dll', vim.fn.getcwd() .. '/bin/Debug/', 'file')
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
vim.keymap.set('n', '<Leader>dj', dap.step_into)
vim.keymap.set('n', '<Leader>dk', dap.step_out)
vim.keymap.set('n', '<Leader>dh', dap.step_over)
vim.keymap.set('n', '<Leader>dd', dap.toggle_breakpoint)
vim.keymap.set('n', '<Leader>dD', "<cmd>dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>")
vim.keymap.set('n', '<Leader>do', dap.repl.open)
vim.keymap.set('n', '<Leader>dR', dap.run_last)

