-- nvim-dap with netcoredbg (modules/debugging) for .NET. Starting a session is
-- config/dotnet_debug: <Leader>dr the buffer's project, <Leader>dR a picked
-- one, <Leader>dt the test or test class under the cursor.
local function dotnet(action)
  return function() require('config.dotnet_debug')[action]() end
end

return {
  'mfussenegger/nvim-dap',
  dependencies = {
    { 'rcarriga/nvim-dap-ui', dependencies = { 'nvim-neotest/nvim-nio' } },
    'theHamsta/nvim-dap-virtual-text',
  },
  keys = {
    { '<Leader>dr', dotnet('debug_current'), desc = 'Debug: project of the buffer (or continue)' },
    { '<Leader>dR', dotnet('debug_pick'), desc = 'Debug: pick a project' },
    { '<Leader>dt', dotnet('debug_test'), desc = 'Debug: test/test class under the cursor' },
    { '<Leader>d.', dotnet('repeat_last'), desc = 'Debug: repeat the last' },
    { '<Leader>ds', dotnet('stop'), desc = 'Debug: stop (detach when attached)' },
    { '<Leader>dh', function() require('dap').continue() end, desc = 'Debug: continue' },
    { '<Leader>dl', function() require('dap').step_over() end, desc = 'Debug: step over' },
    { '<Leader>dk', function() require('dap').step_out() end, desc = 'Debug: step out' },
    { '<Leader>dj', function() require('dap').step_into() end, desc = 'Debug: step into' },
    { '<Leader>dd', function() require('dap').toggle_breakpoint() end, desc = 'Debug: breakpoint' },
    { '<Leader>dD', function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = 'Debug: conditional breakpoint' },
    { '<Leader>do', function() require('dap').repl.open() end, desc = 'Debug: REPL' },
  },
  config = function()
    local dap, dapui = require('dap'), require('dapui')

    dap.adapters.coreclr = {
      type = 'executable',
      command = vim.env.HOME .. '/.local/bin/netcoredbg',
      args = { '--interpreter=vscode' },
    }

    require('nvim-dap-virtual-text').setup({})
    dapui.setup()
    dap.listeners.after.event_initialized.dapui_config = dapui.open
    dap.listeners.before.event_terminated.dapui_config = dapui.close
    dap.listeners.before.event_exited.dapui_config = dapui.close
    -- Detaching (<Leader>ds on an attached process) ends with no terminated event
    dap.listeners.after.disconnect.dapui_config = dapui.close
  end,
}
