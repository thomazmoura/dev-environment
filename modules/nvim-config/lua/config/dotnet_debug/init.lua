-- .NET debugging the way VS Code does it, on nvim-dap and netcoredbg. The keys
-- are in lua/plugins/debug.lua; README.md has how each one works.
--   <Leader>dr  debug the buffer's project (continues a running session; attaches
--               to the project's `dotnet watch` app when there is one)
--   <Leader>dR  debug a project picked from the runnable ones under the cwd
--   <Leader>dt  debug the test method, or the test class, under the cursor
--   <Leader>d.  repeat the last of those
--   <Leader>ds  stop (detach from an attached process, leaving it running)
local project = require('config.dotnet_debug.project')

local M = {}

local last -- what <Leader>d. repeats
local last_ns = vim.api.nvim_create_namespace('dotnet_debug_last')

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = '.NET debug' })
end

local function start(csproj, properties, tfm)
  local name = project.name(csproj)
  local dap = require('dap')

  local pid = require('config.dotnet_debug.watch').find(properties.TargetPath)
  if pid then
    -- The runtime refuses hot reload while a debugger is attached, and watch
    -- then stops sending changes to that process until it restarts it
    notify(string.format('Attaching to %s under dotnet watch (pid %d); <Leader>ds detaches.\n'
      .. 'Hot reload is off while attached: a change saved now needs Ctrl+R in dotnet watch.', name, pid))
    return dap.run({ type = 'coreclr', request = 'attach', name = name .. ' (dotnet watch)', processId = pid })
  end

  notify('Building ' .. name .. '…')
  project.save_buffers()
  project.build(csproj, tfm, function(ok, message)
    if not ok then return notify(name .. ': build failed\n' .. message, vim.log.levels.ERROR) end
    local launch = project.launch_settings(csproj)
    dap.run({
      type = 'coreclr',
      request = 'launch',
      name = name .. (launch.name and (' (' .. launch.name .. ')') or ''),
      program = properties.TargetPath,
      cwd = vim.fs.dirname(csproj), -- as `dotnet run`: the content root
      args = launch.args,
      env = launch.env,
    })
  end)
end

local function debug_project(csproj, tfm)
  last = { kind = 'project', csproj = csproj, tfm = tfm }
  project.properties(csproj, tfm, function(properties, err)
    if not properties then return notify(err, vim.log.levels.ERROR) end
    local name = project.name(csproj)

    if properties.TargetPath == '' and properties.TargetFrameworks ~= '' then
      local tfms = vim.split(properties.TargetFrameworks, ';', { trimempty = true })
      return vim.ui.select(tfms, { prompt = name .. ': target framework' }, function(choice)
        if choice then debug_project(csproj, choice) end
      end)
    end

    local output_type = properties.OutputType:lower()
    if properties.IsTestProject:lower() == 'true' or (output_type ~= 'exe' and output_type ~= 'winexe') then
      notify(name .. ' does not start a process (tests: <Leader>dt); pick the project to run',
        vim.log.levels.WARN)
      return M.debug_pick()
    end
    start(csproj, properties, tfm)
  end)
end

function M.debug_current()
  local dap = require('dap')
  if dap.session() then return dap.continue() end
  local csproj = project.for_buffer(0)
  if not csproj then return M.debug_pick() end
  debug_project(csproj)
end

function M.debug_pick()
  local cwd = vim.fn.getcwd()
  local projects = project.runnable(cwd)
  if #projects == 0 then return notify('No runnable .NET project under ' .. cwd, vim.log.levels.WARN) end
  vim.ui.select(projects, {
    prompt = 'Debug project',
    format_item = function(csproj) return vim.fs.relpath(cwd, csproj) or csproj end,
  }, function(csproj)
    if csproj then debug_project(csproj) end
  end)
end

local function debug_test_at(buf, pos)
  if not require('config.dotnet_debug.test').debug(buf, pos) then return end
  -- An extmark, so <Leader>d. still finds the test after edits above it
  vim.api.nvim_buf_clear_namespace(buf, last_ns, 0, -1)
  last = { kind = 'test', buf = buf, mark = vim.api.nvim_buf_set_extmark(buf, last_ns, pos[1], pos[2], {}) }
end

function M.debug_test()
  local cursor = vim.api.nvim_win_get_cursor(0)
  debug_test_at(vim.api.nvim_get_current_buf(), { cursor[1] - 1, cursor[2] })
end

function M.repeat_last()
  if not last then return notify('Nothing debugged yet', vim.log.levels.WARN) end
  if last.kind == 'project' then return debug_project(last.csproj, last.tfm) end
  if not vim.api.nvim_buf_is_valid(last.buf) then return notify('The last test\'s buffer is gone', vim.log.levels.WARN) end
  local pos = vim.api.nvim_buf_get_extmark_by_id(last.buf, last_ns, last.mark, {})
  if not pos[1] then return notify('The last test is gone', vim.log.levels.WARN) end
  debug_test_at(last.buf, pos)
end

-- The " at Method in /file.cs:line N" lines of an exception's stack traces (its own
-- and its inner exceptions'), innermost exception first
local function user_frames(details, items)
  items = items or {}
  for _, inner in ipairs(details.innerException or {}) do user_frames(inner, items) end
  for line in (details.stackTrace or ''):gmatch('[^\n]+') do
    local method, file, lnum = line:match('^%s*at (.-) in (.+):line (%d+)%s*$')
    if method then
      table.insert(items, { filename = file, lnum = tonumber(lnum), text = (details.typeName or '') .. ' in ' .. method })
    end
  end
  return items
end

-- netcoredbg breaks on an unhandled exception where it's rethrown. Thrown from an
-- async Main (a host that fails to start), that's ExceptionDispatchInfo.Throw()
-- under the generated <Main>(), with no frame that has a source: dap only says
-- "Source missing, cannot jump to frame", so show the exception here, with the
-- frames of our code where it was thrown in the quickfix list
function M.on_stopped(session, body)
  if body.reason ~= 'exception' or session.config.type ~= 'coreclr' then return end
  session:request('stackTrace', { threadId = body.threadId, startFrame = 0 }, function(err, trace)
    if err or not trace then return end
    for _, frame in ipairs(trace.stackFrames) do
      if frame.source and frame.source.path then return end -- dap jumps there and shows it
    end
    session:request('exceptionInfo', { threadId = body.threadId }, function(info_err, info)
      if info_err or not info then return notify(body.text or 'Stopped on an exception', vim.log.levels.ERROR) end
      local items = user_frames(info.details or {})
      local message = info.description or body.text
      if items[1] then
        vim.fn.setqflist({}, ' ', { title = info.exceptionId or 'Exception', items = items })
        message = string.format('%s\n\nThrown from %s:%d; :copen lists its frames in our code.',
          message, vim.fn.fnamemodify(items[1].filename, ':~:.'), items[1].lnum)
      end
      notify(message, vim.log.levels.ERROR)
    end)
  end)
end

-- An attached process (dotnet watch's app, a test host) keeps running
function M.stop()
  local dap = require('dap')
  local session = dap.session()
  if not session then return end
  if session.config.request == 'attach' then
    dap.disconnect({ terminateDebuggee = false })
  else
    dap.terminate()
  end
end

return M
