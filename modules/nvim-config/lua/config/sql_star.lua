-- gd on the * of a SELECT * in a SQL Server buffer replaces it with the columns it stands
-- for, as SQL Prompt does in SSMS; anywhere else, gd goes to the definition (the keymap is in
-- lua/plugins/database.lua). Through a join each column gets its table's alias (c.Id, o.Id),
-- and o.* gets o's columns, each with o.
--
-- ScriptDom (config/sql_split_sqlserver.lua) finds the * and what its FROM reads from. SQL
-- Server's sys.dm_exec_describe_first_result_set gives the columns of a SELECT that has only
-- that FROM (and the statement's CTEs), one marker column ahead of each table's, through the
-- buffer's dadbod connection: so views, subqueries, CTEs and APPLY expand as the server
-- itself would, and WHERE's @variables, left out, need no DECLARE. A FROM reading a #temp
-- table or a @table variable can't be described.
local M = {}

local MARKER = '__nvim_star_'
local SEP = '\31'
-- Wider than this, the columns go one per line, under the first, and what followed the *
-- (FROM...) on a line of its own
local MAX_WIDTH = 100
-- How long the server may take to describe the query, in ms
local TIMEOUT = 30000

local function notify(message, level)
  vim.notify('Expand *: ' .. message, level or vim.log.levels.WARN)
end

--- The SQL of the probe: the * as one marker plus `x.*` per table, over its FROM alone
local function probe(star)
  local items = {}
  if star.qualifier then
    items = { ('0 AS [%s0], %s.*'):format(MARKER, star.qualifier) }
  elseif #star.sources == 1 then
    items = { ('0 AS [%s0], *'):format(MARKER) }
  else
    for i, source in ipairs(star.sources) do
      items[i] = ('0 AS [%s%d], %s.*'):format(MARKER, i - 1, source)
    end
  end
  return (star.with and (star.with .. ' ') or '') .. 'SELECT ' .. table.concat(items, ', ') .. ' ' .. star.from
end

--- callback(columns) with one list of names per table of the *, or callback(nil, error)
local function describe(url, star, callback)
  local query = ("SET NOCOUNT ON; SELECT ISNULL(name, ''), ISNULL(error_message, '')"
    .. " FROM sys.dm_exec_describe_first_result_set(N'%s', NULL, 0) ORDER BY column_ordinal")
    :format(probe(star):gsub("'", "''"))
  local ok, cmd = pcall(vim.fn['sqlserver_locksmith#interactive'], url)
  if not ok then return callback(nil, cmd) end
  vim.list_extend(cmd, { '-b', '-h', '-1', '-W', '-s', SEP, '-Q', query })
  vim.system(cmd, { text = true, timeout = TIMEOUT }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      return callback(nil, vim.trim((result.stdout or '') .. (result.stderr or '')))
    end
    local columns = {}
    for line in vim.gsplit(vim.trim(result.stdout), '\n') do
      local name, err = unpack(vim.split(vim.trim(line), SEP, { plain = true }))
      if err and err ~= '' then return callback(nil, err) end
      if name:find('^' .. MARKER .. '%d+$') then
        table.insert(columns, {})
      elseif #columns > 0 then
        table.insert(columns[#columns], name)
      end
    end
    if #columns == 0 then return callback(nil, 'the server described no columns') end
    callback(columns)
  end))
end

--- The column list replacing the *, given the quoted names
local function select_list(star, columns, quoted)
  local items, n = {}, 0
  for i, names in ipairs(columns) do
    local prefix = star.qualifier or (#star.sources > 1 and star.sources[i]) or nil
    for _ = 1, #names do
      n = n + 1
      table.insert(items, prefix and (prefix .. '.' .. quoted[n]) or quoted[n])
    end
  end
  return items
end

--- Replaces the * under the cursor with its columns
function M.expand()
  local buf = vim.api.nvim_get_current_buf()
  local url = require('config.sql_dialect').dadbod_url(buf)
  if url then
    require('lazy').load({ plugins = { 'vim-dadbod' } })
    url = vim.fn['db#resolve'](url)
  end
  if not url or not url:match('^sqlserver:') then
    return notify('the buffer has no SQL Server connection (dadbod) to read the columns from')
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, '\n')
  local starts, offset = {}, 0
  for i, line in ipairs(lines) do
    starts[i] = offset
    offset = offset + #line + 1
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local tick = vim.b[buf].changedtick

  local parser = require('config.sql_split_sqlserver')
  parser.request({ kind = 'star', text = text, cursor = starts[row] + col }, function(star, err)
    if err then return notify(err, vim.log.levels.ERROR) end
    if not star.star then return notify('the cursor is not on the * of a select list') end
    describe(url, star, function(columns, describe_err)
      if describe_err then return notify(describe_err, vim.log.levels.ERROR) end
      parser.request({ kind = 'quote', names = vim.iter(columns):flatten():totable() }, function(answer, quote_err)
        if quote_err then return notify(quote_err, vim.log.levels.ERROR) end
        if vim.b[buf].changedtick ~= tick then return notify('the buffer changed meanwhile') end

        local items = select_list(star, columns, answer.names)
        local first, last = star.star[1], star.star[2]
        local srow = row
        while starts[srow] > first do srow = srow - 1 end
        while starts[srow + 1] and starts[srow + 1] <= first do srow = srow + 1 end
        local erow = srow
        while starts[erow + 1] and starts[erow + 1] <= last do erow = erow + 1 end
        local scol, ecol = first - starts[srow], last - starts[erow]

        local before, after = lines[srow]:sub(1, scol), lines[erow]:sub(ecol + 1)
        local joined = table.concat(items, ', ')
        local replacement = { joined }
        if vim.fn.strdisplaywidth(before .. joined .. after) > MAX_WIDTH then
          local indent = string.rep(' ', vim.fn.strdisplaywidth(before))
          replacement = vim.tbl_map(function(item) return indent .. item .. ',' end, items)
          replacement[1] = replacement[1]:sub(#indent + 1)
          replacement[#replacement] = replacement[#replacement]:sub(1, -2)
          if vim.trim(after) ~= '' then
            table.insert(replacement, lines[srow]:match('^%s*') .. vim.trim(after))
            ecol = #lines[erow]
          end
        end
        vim.api.nvim_buf_set_text(buf, srow - 1, scol, erow - 1, ecol, replacement)
      end)
    end)
  end)
end

--- gd: the * of a select list expands, anything else goes to its definition
function M.definition()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  if line:sub(col + 1, col + 1) == '*' and vim.b.sql_dialect == 'sqlserver' then return M.expand() end
  vim.lsp.buf.definition()
end

return M
