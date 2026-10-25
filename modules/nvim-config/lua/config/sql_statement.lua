-- The statement under the cursor in a sql buffer, run alone through dadbod (<Leader>r in
-- lua/plugins/database.lua), like the mssql/pgsql extensions' runCurrentStatement in VS Code.
--
-- A statement ends at a blank line, a GO line or a line ending in ';', so a file of queries
-- separated by any of them runs one at a time. A query with a blank line inside runs only
-- the part around the cursor: select it and use the visual <Leader>r instead.
local M = {}

local ns = vim.api.nvim_create_namespace('sql_statement')

local function is_separator(line)
  return line:match('^%s*$') ~= nil or line:lower():match('^%s*go%s*%d*%s*$') ~= nil
end

-- A trailing -- comment doesn't hide the ';' before it
local function ends_statement(line)
  return line:gsub('%-%-.*$', ''):match(';%s*$') ~= nil
end

-- First and last line (1-based) of the statement around `row`, nil if there is none
function M.range(buf, row)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- On a blank or GO line, the statement just above it (the one usually just written)
  while row >= 1 and is_separator(lines[row]) do row = row - 1 end
  if row < 1 then return nil end

  local first = row
  while first > 1 and not is_separator(lines[first - 1]) and not ends_statement(lines[first - 1]) do
    first = first - 1
  end

  local last = row
  while not ends_statement(lines[last]) and last < #lines and not is_separator(lines[last + 1]) do
    last = last + 1
  end

  return first, last
end

function M.run()
  local buf = vim.api.nvim_get_current_buf()
  local first, last = M.range(buf, vim.api.nvim_win_get_cursor(0)[1])
  if not first then
    return vim.notify('No statement under the cursor', vim.log.levels.WARN)
  end

  -- A flash of what was sent, since nothing else shows where the statement was cut
  vim.hl.range(buf, ns, 'IncSearch', { first - 1, 0 }, { last - 1, 0 }, { regtype = 'V', timeout = 300 })
  vim.cmd(first .. ',' .. last .. 'DB')
end

return M
