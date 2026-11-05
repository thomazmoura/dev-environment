-- How values of chosen types show in the debugger: netcoredbg shows a struct
-- like Guid or DateTime as its type name ({System.Guid}), so for the types in
-- `formatters` the value is replaced by an expression evaluated in the debuggee
-- (`x.ToString()`). Only the text changes: the value still expands into its
-- members. It applies to the inline virtual text, dap-ui's panes and gH's popup.
-- lua/plugins/debug.lua calls setup(), with the personal overrides.
local M = {}

-- formatters: keyed by the type netcoredbg reports. A value is
--   string:   an expression, {value} replaced by the variable's expression
--   function: fun(expr, item) -> an expression, or nil to leave the value alone
--   false:    turns a default off
M.defaults = {
  enabled = true,
  unquote = true, -- 54b3… rather than "54b3…" (the formatted values are strings)
  timeout_ms = 1000, -- a stuck evaluation never holds the panes: its raw value is kept
  formatters = {
    ['System.Guid'] = '{value}.ToString()',
    ['System.DateTime'] = '{value}.ToString("s")', -- 2021-11-30T20:36:45
    ['System.DateTimeOffset'] = '{value}.ToString("yyyy-MM-ddTHH:mm:sszzz")',
    ['System.DateOnly'] = '{value}.ToString("yyyy-MM-dd")',
    ['System.TimeOnly'] = '{value}.ToString("HH:mm:ss")',
    ['System.TimeSpan'] = '{value}.ToString()',
  },
}

local options = vim.deepcopy(M.defaults)

-- The formatter of a type, a nullable one's (`T?`, Nullable<T>) included
local function formatter_for(type_name)
  if not type_name then return end
  local formatter = options.formatters[type_name]
  if formatter == nil then
    local inner = type_name:match('^(.-)%?$')
      or type_name:match('^System%.Nullable<(.+)>$')
      or type_name:match('^System%.Nullable`1%[(.+)%]$')
    if inner then formatter = options.formatters[inner] end
  end
  return formatter or nil
end

local function expression_for(item, expr)
  local formatter = formatter_for(item.type)
  if not formatter or not expr or expr == '' then return end
  -- `a + b` has to be (a + b).ToString(); a plain member chain needs nothing
  if not expr:match('^[%a_][%w_%.]*$') then expr = '(' .. expr .. ')' end
  if type(formatter) == 'function' then return formatter(expr, item) end
  return (formatter:gsub('{value}', function() return expr end))
end

local function unquote(text)
  local inner = options.unquote and text:match('^"(.*)"$')
  if not inner then return text end
  return (inner:gsub('\\(.)', '%1'))
end

-- Replaces the value of each item of a variables/evaluate response that has a
-- formatter, then calls done() (once, even when evaluations time out)
local function format(session, request, command, args, response, done)
  local frame_id = (command == 'evaluate' and args.frameId)
    or (session.current_frame and session.current_frame.id)
  local jobs = {}
  if response and frame_id then
    if command == 'variables' then
      for _, variable in ipairs(response.variables or {}) do
        if variable.value ~= 'null' then
          local expr = expression_for(variable, variable.evaluateName)
          if expr then table.insert(jobs, { item = variable, field = 'value', expr = expr }) end
        end
      end
    elseif response.result ~= 'null' then
      local expr = expression_for(response, args.expression)
      if expr then table.insert(jobs, { item = response, field = 'result', expr = expr }) end
    end
  end
  if #jobs == 0 then return done() end

  local pending, finished = #jobs, false
  local function finish()
    if finished then return end
    finished = true
    done()
  end
  for _, job in ipairs(jobs) do
    local eval_args = { expression = job.expr, frameId = frame_id, context = 'hover' }
    request(session, 'evaluate', eval_args, function(err, result)
      if not finished and not err and result and result.result then
        job.item[job.field] = unquote(result.result)
      end
      pending = pending - 1
      if pending == 0 then finish() end
    end)
  end
  vim.defer_fn(finish, options.timeout_ms)
end

local function refresh_virtual_text(session)
  local virtual_text = package.loaded['nvim-dap-virtual-text']
  if virtual_text then virtual_text.refresh(session) end
end

-- Puts the formatting between the session and whoever asked (dap's scopes,
-- which the virtual text reads, dap-ui's panes and popups)
local function wrap(session)
  if not session or session.dotnet_display_wrapped then return end
  if not (session.config and session.config.type == 'coreclr') then return end
  session.dotnet_display_wrapped = true
  local request = session.request

  session.request = function(self, command, args, on_result)
    if not options.enabled or (command ~= 'variables' and command ~= 'evaluate') then
      return request(self, command, args, on_result)
    end
    local co, is_main
    if not on_result then
      co, is_main = coroutine.running()
      if not co or is_main then return request(self, command, args, on_result) end
    end
    request(self, command, args, function(err, response, ...)
      local rest = { ... }
      format(self, request, command, args or {}, not err and response or nil, function()
        if co then
          local ok, msg = coroutine.resume(co, err, response)
          if not ok then error(msg) end
        else
          on_result(err, response, unpack(rest))
        end
        -- The virtual text drew when the response came, before this
        if command == 'variables' then refresh_virtual_text(self) end
      end)
    end)
    if co then return coroutine.yield() end
  end
end

function M.setup(opts)
  options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  local dap = require('dap')
  dap.listeners.on_session.dotnet_display = function(_, new_session) wrap(new_session) end
  -- In case a session got past on_session (one that was never the focused one)
  dap.listeners.before.event_stopped.dotnet_display = function(session) wrap(session) end
  wrap(dap.session())
end

return M
