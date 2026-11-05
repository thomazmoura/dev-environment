-- nvim-dap with netcoredbg (modules/debugging) for .NET. Starting a session is
-- config/dotnet_debug: <Leader>dr the buffer's project, <Leader>dR a picked
-- one, <Leader>dt the test or test class under the cursor. While a session
-- runs, each <Leader>d{key} is also <M-{key}> and gH (or <CR>) opens the value
-- under the cursor as an expandable tree in a popup (config/dap_session_keys).
local function dotnet(action)
  return function() require('config.dotnet_debug')[action]() end
end

local function dap(method)
  return function() require('dap')[method]() end
end

-- { key, action, desc }: <Leader>d{key} always, <M-{key}> during a session
local actions = {
  { 'r', dotnet('debug_current'), 'project of the buffer (or continue)' },
  { 'R', dotnet('debug_pick'), 'pick a project' },
  { 't', dotnet('debug_test'), 'test/test class under the cursor' },
  { '.', dotnet('repeat_last'), 'repeat the last' },
  { 's', dotnet('stop'), 'stop (detach when attached)' },
  { 'h', dap('continue'), 'continue' },
  { 'j', dap('step_over'), 'step over' },
  { 'k', dap('step_out'), 'step out' },
  { 'l', dap('step_into'), 'step into' },
  { 'd', dap('toggle_breakpoint'), 'breakpoint' },
  { 'D', function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, 'conditional breakpoint' },
  { 'o', function() require('dap').repl.open() end, 'REPL' },
}

local keys, session_keys = {}, {}
for _, action in ipairs(actions) do
  local key, rhs, desc = action[1], action[2], 'Debug: ' .. action[3]
  table.insert(keys, { '<Leader>d' .. key, rhs, desc = desc })
  table.insert(session_keys, { '<M-' .. key .. '>', rhs, desc })
end

-- VS Code's debug hover (gH there too): the value under the cursor in a centered
-- popup sized like Workhorse's, as the tree the Watches pane shows (<CR> expands,
-- e edits, q closes)
local function inspect()
  local expr = vim.fn.expand('<cexpr>')
  if expr == '' then
    vim.notify('Nothing to inspect under the cursor', vim.log.levels.WARN)
    return
  end
  local columns, lines = vim.o.columns - 2, vim.o.lines - vim.o.cmdheight - 2
  require('dapui').eval(expr, {
    enter = true,
    position = 'center',
    width = math.floor(columns * 0.8),
    height = math.floor(lines * 0.8),
    title = ' ' .. expr .. ' ',
  })
end
table.insert(session_keys, { 'gH', inspect, 'Debug: inspect the value under the cursor' })
-- <CR> too, in file buffers: special ones (quickfix, terminal, the command-line
-- window) keep Vim's own <CR>. Plugins' buffer-local <CR> (dap-ui's expand,
-- nvim-tree, Trouble) wins over this anyway
table.insert(session_keys, { '<CR>', function()
  if vim.bo.buftype ~= '' then
    vim.api.nvim_feedkeys(vim.v.count1 .. vim.keycode('<CR>'), 'n', false)
  else
    inspect()
  end
end, 'Debug: inspect the value under the cursor' })

return {
  'mfussenegger/nvim-dap',
  dependencies = {
    { 'rcarriga/nvim-dap-ui', dependencies = { 'nvim-neotest/nvim-nio' } },
    'theHamsta/nvim-dap-virtual-text',
  },
  keys = keys,
  config = function()
    local dap, dapui = require('dap'), require('dapui')

    dap.adapters.coreclr = {
      type = 'executable',
      command = vim.env.HOME .. '/.local/bin/netcoredbg',
      args = { '--interpreter=vscode' },
    }

    -- VS Code's gutter: codicons (Nerd Font), red breakpoints, a gray rejected
    -- one, a yellow arrow and a faint yellow line where execution stopped
    local function debug_highlights()
      local function hex(n) return string.format('#%06x', n) end
      local function blend(fg, bg, alpha)
        local channels = {}
        for shift = 16, 0, -8 do
          local f, b = bit.band(bit.rshift(fg, shift), 0xff), bit.band(bit.rshift(bg, shift), 0xff)
          table.insert(channels, math.floor(f * alpha + b * (1 - alpha) + 0.5))
        end
        return channels[1] * 0x10000 + channels[2] * 0x100 + channels[3]
      end
      local normal_bg = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg or 0x1e1e1e
      vim.api.nvim_set_hl(0, 'DapBreakpointSign', { fg = '#e51400' })
      vim.api.nvim_set_hl(0, 'DapBreakpointRejectedSign', { fg = '#848484' })
      vim.api.nvim_set_hl(0, 'DapStoppedSign', { fg = '#ffcc00' })
      vim.api.nvim_set_hl(0, 'DapStoppedLine', { bg = hex(blend(0xffcc00, normal_bg, 0.2)) })
    end
    debug_highlights()
    vim.api.nvim_create_autocmd('ColorScheme', { callback = debug_highlights })
    local signs = {
      DapBreakpoint = { text = '', texthl = 'DapBreakpointSign' }, -- cod-circle_filled
      DapBreakpointCondition = { text = '', texthl = 'DapBreakpointSign' }, -- cod-debug_breakpoint_conditional
      DapLogPoint = { text = '', texthl = 'DapBreakpointSign' }, -- cod-debug_breakpoint_log
      DapBreakpointRejected = { text = '', texthl = 'DapBreakpointRejectedSign' }, -- cod-debug_breakpoint_unsupported
      DapStopped = { text = '', texthl = 'DapStoppedSign', linehl = 'DapStoppedLine', numhl = 'DapStoppedSign' }, -- cod-debug_stackframe
    }
    for name, sign in pairs(signs) do vim.fn.sign_define(name, sign) end

    require('nvim-dap-virtual-text').setup({})
    -- Rounded like Workhorse's and Paperboy's popups
    dapui.setup({ floating = { border = 'rounded' } })
    require('config.dap_session_keys').setup(session_keys)
    dap.listeners.after.event_initialized.dapui_config = dapui.open
    dap.listeners.before.event_terminated.dapui_config = dapui.close
    dap.listeners.before.event_exited.dapui_config = dapui.close
    -- Detaching (<Leader>ds on an attached process) ends with no terminated event
    dap.listeners.after.disconnect.dapui_config = dapui.close
    -- An unhandled exception with no frame to jump to (one that stops the host)
    dap.listeners.after.event_stopped.dotnet_debug = function(session, body)
      require('config.dotnet_debug').on_stopped(session, body)
    end
  end,
}
