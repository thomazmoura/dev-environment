return {
  'mfussenegger/nvim-dap',
  dependencies = {
    { 'rcarriga/nvim-dap-ui', dependencies = { 'nvim-neotest/nvim-nio' } },
    'theHamsta/nvim-dap-virtual-text',
  },
  keys = {
    { '<Leader>dr', function() require('dap').continue() end, desc = 'Debug: run/continue' },
    { '<Leader>dh', function() require('dap').continue() end, desc = 'Debug: continue' },
    { '<Leader>dl', function() require('dap').step_over() end, desc = 'Debug: step over' },
    { '<Leader>dk', function() require('dap').step_out() end, desc = 'Debug: step out' },
    { '<Leader>dj', function() require('dap').step_into() end, desc = 'Debug: step into' },
    { '<Leader>dd', function() require('dap').toggle_breakpoint() end, desc = 'Debug: breakpoint' },
    { '<Leader>dD', function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = 'Debug: conditional breakpoint' },
    { '<Leader>do', function() require('dap').repl.open() end, desc = 'Debug: REPL' },
    { '<Leader>dR', function() require('dap').run_last() end, desc = 'Debug: run last' },
    { '<Leader>ds', function() require('dap').close() end, desc = 'Debug: stop' },
  },
  config = function()
    local dap, dapui = require('dap'), require('dapui')

    dap.adapters.coreclr = {
      type = 'executable',
      command = vim.env.HOME .. '/.local/bin/netcoredbg',
      args = { '--interpreter=vscode' },
    }
    dap.configurations.cs = {
      {
        type = 'coreclr',
        name = 'launch - netcoredbg',
        request = 'launch',
        cwd = function() return vim.fn.input('Path to csproj: ', vim.fn.getcwd(), 'dir') end,
        program = function() return vim.fn.input('Path to dll: ', vim.fn.getcwd(), 'file') end,
      },
    }

    require('nvim-dap-virtual-text').setup({})
    dapui.setup()
    dap.listeners.after.event_initialized.dapui_config = dapui.open
    dap.listeners.before.event_terminated.dapui_config = dapui.close
    dap.listeners.before.event_exited.dapui_config = dapui.close
  end,
}
