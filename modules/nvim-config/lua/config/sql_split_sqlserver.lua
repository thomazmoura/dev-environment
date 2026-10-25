-- Where the T-SQL statements around the cursor start and end, for <Leader>r in sql buffers
-- (config/sql_statement.lua), and what a SELECT * reads from, for gd on it
-- (config/sql_star.lua): asked of sql_split_sqlserver.ps1, which parses with ScriptDom.
-- T-SQL doesn't need a ';' between statements, so only a parser can tell where one ends.
--
-- The script keeps running once started, as it takes a second or two to start (the first
-- time ever, a few more to compile its C#). SQL Server buffers start it ahead (M.warm).
local M = {}

local SCRIPT = debug.getinfo(1, 'S').source:sub(2):gsub('%.lua$', '.ps1')

local process
-- The callbacks of the requests sent, answered in order
local pending = {}

local function fail(message)
  local callbacks = pending
  pending = {}
  for _, callback in ipairs(callbacks) do callback(nil, message) end
end

local function start()
  if process then return true end
  local buffered, errors = '', {}
  local ok, result = pcall(vim.system, { 'pwsh', '-NoProfile', '-NonInteractive', '-File', SCRIPT }, {
    stdin = true,
    stdout = function(_, data)
      if not data then return end
      buffered = buffered .. data
      for line in function() return buffered:match('^([^\n]*)\n') end do
        buffered = buffered:sub(#line + 2)
        vim.schedule(function()
          local callback = table.remove(pending, 1)
          if not callback then return end
          -- JSON's null as nil, not vim.NIL
          local decoded_ok, answer = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
          if not decoded_ok then return callback(nil, line) end
          if answer.error then return callback(nil, answer.error) end
          callback(answer)
        end)
      end
    end,
    stderr = function(_, data)
      if data then table.insert(errors, data) end
    end,
  }, function(exit)
    vim.schedule(function()
      process = nil
      fail(('the T-SQL parser stopped (exit %d): %s'):format(exit.code, vim.trim(table.concat(errors))))
    end)
  end)
  if not ok then
    fail('the T-SQL parser could not start: ' .. result)
    return false
  end
  process = result
  return true
end

--- Starts the script, so the first <Leader>r doesn't wait for it
function M.warm() start() end

--- callback(answer) or callback(nil, error) for one of the script's requests (see its top)
function M.request(request, callback)
  table.insert(pending, callback)
  if start() then process:write(vim.json.encode(request) .. '\n') end
end

--- callback({{start, end}, ...}) with UTF-8 byte offsets, the end excluded, for the
--- statements of the cursor's GO batch up to the first ending past `cursor`, or
--- callback(nil, error)
function M.split(text, cursor, callback)
  M.request({ text = text, cursor = cursor }, function(answer, err)
    callback(answer and answer.statements, err)
  end)
end

return M
