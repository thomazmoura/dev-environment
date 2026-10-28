-- Completes an INSERT's column list with all the table's columns, as SQL Prompt does in SSMS:
-- after
--   INSERT INTO dbo.Orders (
-- the first item is CustomerId, OrderDate, Total, to accept and then trim. Blink's 'sql_insert'
-- provider (lua/plugins/completion.lua), for SQL Server buffers. A '(' opens the menu in sql
-- buffers only there: completion.lua blocks it elsewhere with M.after_insert.
--
-- The columns come from sys.columns over the buffer's dadbod connection, asked on every such
-- '(' so they follow the table's changes, in the table's order. Identity, computed and
-- rowversion columns are left out, as an INSERT can't set them. The table is found by
-- OBJECT_ID, so #temp tables, which live in the buffer's own session, get nothing.
local M = {}

local SEP = '\31'
-- How long the server may take to list the columns, in ms
local TIMEOUT = 30000
-- How many lines above the cursor the INSERT may start
local LINES = 20

local QUERY = table.concat({
  'SET NOCOUNT ON;',
  'SELECT c.name, TYPE_NAME(c.user_type_id) FROM sys.columns c',
  "WHERE c.object_id = OBJECT_ID(N'%s') AND c.is_identity = 0 AND c.is_computed = 0",
  "AND TYPE_NAME(c.system_type_id) <> 'timestamp'",
  'ORDER BY c.column_id',
}, ' ')

--- Whether text is a table's name as written: parts like dbo, [My Table] or "x", joined by dots
local function is_name(text)
  local i = 1
  while true do
    local part = text:match('^%b[]', i) or text:match('^"[^"]*"', i) or text:match('^[%w_@#$]+', i)
    if not part then return false end
    i = i + #part
    if i > #text then return true end
    if text:sub(i, i) ~= '.' then return false end
    i = i + 1
  end
end

--- The table named by the INSERT whose column list is opened right before the cursor, as
--- written, and the column the word being typed after its '(' starts at (0-based), or nil
--- when the text before the cursor isn't `INSERT [INTO] <table> (<word>`. It may span lines
function M.after_insert(buf, row, col)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
    row, col = unpack(vim.api.nvim_win_get_cursor(0))
  end
  if vim.bo[buf].filetype ~= 'sql' then return nil end
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:sub(1, col)
  local word = line:match('%(%s*([%w_]*)$')
  if not word then return nil end
  local lines = vim.api.nvim_buf_get_lines(buf, math.max(0, row - 1 - LINES), row - 1, false)
  table.insert(lines, line)
  local text = table.concat(lines, '\n')

  -- After the last INSERT
  local last
  for at in text:gmatch('()%f[%w_][Ii][Nn][Ss][Ee][Rr][Tt]%f[^%w_]') do last = at end
  if not last then return nil end
  local rest = text:sub(last + #'INSERT'):gsub('^%s+[Ii][Nn][Tt][Oo]%f[^%w_]', '')
  local name = rest:match('^%s+(.-)%s*%(%s*[%w_]*$')
  if name and is_name(name) then return name, col - #word end
end

local source = {}

function source.new() return setmetatable({}, { __index = source }) end

function source:enabled() return vim.b.sql_dialect == 'sqlserver' end

function source:get_trigger_characters() return { '(' } end

function source:get_completions(context, callback)
  local function answer(items)
    callback({ items = items or {}, is_incomplete_forward = false, is_incomplete_backward = false })
  end
  local name = M.after_insert(context.bufnr, context.cursor[1], context.cursor[2])
  if not name then return answer() end
  local url = require('config.sql_dialect').dadbod_url(context.bufnr)
  if url then
    require('lazy').load({ plugins = { 'vim-dadbod' } })
    url = vim.fn['db#resolve'](url)
  end
  if not url or not url:match('^sqlserver:') then return answer() end

  local ok, cmd = pcall(vim.fn['sqlserver_locksmith#interactive'], url)
  if not ok then return answer() end
  vim.list_extend(cmd, { '-b', '-h', '-1', '-W', '-s', SEP, '-Q', QUERY:format((name:gsub("'", "''"))) })
  vim.system(cmd, { text = true, timeout = TIMEOUT }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify('Insert columns: ' .. vim.trim((result.stdout or '') .. (result.stderr or '')), vim.log.levels.WARN)
      return answer()
    end
    local names, types = {}, {}
    for line in vim.gsplit(vim.trim(result.stdout), '\n') do
      local fields = vim.split(vim.trim(line), SEP, { plain = true })
      if #fields == 2 then
        table.insert(names, fields[1])
        table.insert(types, fields[2])
      end
    end
    if #names == 0 then return answer() end
    require('config.sql_split_sqlserver').request({ kind = 'quote', names = names }, function(quoted, err)
      if err then return answer() end
      local text = table.concat(quoted.names, ', ')
      local documentation = {}
      for i, column in ipairs(quoted.names) do documentation[i] = column .. ' ' .. types[i] end
      answer({ {
        label = text,
        insertText = text,
        labelDetails = { description = ('%d columns'):format(#names) },
        documentation = name .. '\n\n' .. table.concat(documentation, '\n'),
        kind = vim.lsp.protocol.CompletionItemKind.Field,
      } })
    end)
  end))
end

M.new = source.new

return M
