-- Completes a join's ON with the conditions of the foreign keys between the table it joins
-- and the ones before it, as SQL Prompt does in SSMS: after
--   FROM Orders o INNER JOIN Customers c ON
-- the first item is o.CustomerId = c.Id. Blink's 'sql_join' provider (lua/plugins/completion.lua),
-- for SQL Server buffers. A space opens the menu after an ON only: completion.lua unblocks it
-- there with M.after_on.
--
-- ScriptDom (config/sql_split_sqlserver.lua) finds the join and its tables, and the foreign
-- keys come from sys.foreign_keys over the buffer's dadbod connection, read once per
-- connection and NeoVim. They match by schema and table, never by column name, so views,
-- subqueries, CTEs and #temp tables get nothing. Each key is one item, its columns joined by
-- AND; the tables joined last come first.
local M = {}

local SEP = '\31'
-- How long the server may take to list the foreign keys, in ms
local TIMEOUT = 30000

local QUERY = table.concat({
  'SET NOCOUNT ON;',
  'SELECT SCHEMA_NAME();',
  'SELECT fk.object_id, fk.name, SCHEMA_NAME(p.schema_id), p.name, pc.name, SCHEMA_NAME(r.schema_id), r.name, rc.name',
  'FROM sys.foreign_keys fk',
  'JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id',
  'JOIN sys.tables p ON p.object_id = fk.parent_object_id',
  'JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id',
  'JOIN sys.tables r ON r.object_id = fk.referenced_object_id',
  'JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id',
  'ORDER BY fk.object_id, fkc.constraint_column_id',
}, ' ')

-- Resolved dadbod URL → { schema = the login's default schema, keys = { ... } }, or
-- { waiting = { callbacks } } while the query runs
local cache = {}

--- The column the word being typed after an ON starts at (0-based), or nil when the text
--- before the cursor isn't `ON <word>`. ON may end a line above
function M.after_on(buf, row, col)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
    row, col = unpack(vim.api.nvim_win_get_cursor(0))
  end
  if vim.bo[buf].filetype ~= 'sql' then return nil end
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:sub(1, col)
  local word = line:match('[%w_]*$')
  local before = line:sub(1, #line - #word)
  while before:match('^%s*$') and row > 1 do
    row = row - 1
    before = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] .. ' '
  end
  if before:match('%f[%w_][Oo][Nn]%s+$') then return col - #word end
end

local function key(schema, table) return (schema .. '.' .. table):lower() end

--- callback(entry) with the connection's foreign keys, or callback(nil, error)
local function foreign_keys(url, callback)
  local entry = cache[url]
  if entry and entry.keys then return callback(entry) end
  if entry then return table.insert(entry.waiting, callback) end
  entry = { waiting = { callback } }
  cache[url] = entry

  local function done(result, err)
    -- A failure is asked again on the next ON
    cache[url] = result
    for _, waiting in ipairs(entry.waiting) do waiting(result, err) end
  end
  local ok, cmd = pcall(vim.fn['sqlserver_locksmith#interactive'], url)
  if not ok then return done(nil, cmd) end
  vim.list_extend(cmd, { '-b', '-h', '-1', '-W', '-s', SEP, '-Q', QUERY })
  vim.system(cmd, { text = true, timeout = TIMEOUT }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then return done(nil, vim.trim((result.stdout or '') .. (result.stderr or ''))) end
    local found, schema, by_id = {}, nil, {}
    for line in vim.gsplit(vim.trim(result.stdout), '\n') do
      local fields = vim.split(vim.trim(line), SEP, { plain = true })
      if not schema then
        schema = fields[1]
      elseif #fields == 8 then
        local id, name, ps, pt, pc, rs, rt, rc = unpack(fields)
        if not by_id[id] then
          by_id[id] = { name = name, parent = key(ps, pt), referenced = key(rs, rt), columns = {},
            description = ('%s.%s → %s.%s'):format(ps, pt, rs, rt) }
          table.insert(found, by_id[id])
        end
        table.insert(by_id[id].columns, { pc, rc })
      end
    end
    done({ schema = schema or 'dbo', keys = found })
  end))
end

--- The conditions, nearest tables first: { earlier = 'o', joined = 'c', columns = {{ 'CustomerId',
--- 'Id' }}, fk = <its key> }, each pair of columns as { earlier's, joined's }, still unquoted
local function conditions(join, fks)
  local function key_of(t) return key(t.schema or fks.schema, t.table) end
  local function swap(columns) return vim.tbl_map(function(c) return { c[2], c[1] } end, columns) end
  local found = {}
  for j = #join.joined, 1, -1 do
    local joined = join.joined[j]
    for e = #join.earlier, 1, -1 do
      local earlier = join.earlier[e]
      for _, fk in ipairs(fks.keys) do
        -- Both, for a table joined to itself through its own key (e.ManagerId = m.Id, e.Id = m.ManagerId)
        local ways = {}
        if fk.parent == key_of(earlier) and fk.referenced == key_of(joined) then table.insert(ways, fk.columns) end
        if fk.parent == key_of(joined) and fk.referenced == key_of(earlier) then table.insert(ways, swap(fk.columns)) end
        for _, columns in ipairs(ways) do
          table.insert(found, { earlier = earlier.name, joined = joined.name, columns = columns, fk = fk })
        end
      end
    end
  end
  return found
end

local source = {}

function source.new() return setmetatable({}, { __index = source }) end

function source:enabled() return vim.b.sql_dialect == 'sqlserver' end

function source:get_trigger_characters() return { ' ' } end

function source:get_completions(context, callback)
  local function answer(items)
    callback({ items = items or {}, is_incomplete_forward = false, is_incomplete_backward = false })
  end
  local buf, row, col = context.bufnr, context.cursor[1], context.cursor[2]
  local start = M.after_on(buf, row, col)
  if not start then return answer() end
  local url = require('config.sql_dialect').dadbod_url(buf)
  if url then
    require('lazy').load({ plugins = { 'vim-dadbod' } })
    url = vim.fn['db#resolve'](url)
  end
  if not url or not url:match('^sqlserver:') then return answer() end

  -- The text with the word after ON taken out, for the placeholder condition to go there
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = 0
  for i = 1, row - 1 do cursor = cursor + #lines[i] + 1 end
  cursor = cursor + start
  lines[row] = lines[row]:sub(1, start) .. lines[row]:sub(col + 1)
  local parser = require('config.sql_split_sqlserver')

  parser.request({ kind = 'join', text = table.concat(lines, '\n'), cursor = cursor }, function(parsed, err)
    if err or not parsed.join or #parsed.join.earlier == 0 then return answer() end
    foreign_keys(url, function(fks, fk_err)
      if fk_err then
        vim.notify('Join conditions: ' .. fk_err, vim.log.levels.WARN)
        return answer()
      end
      local found = conditions(parsed.join, fks)
      if #found == 0 then return answer() end
      local names = {}
      for _, condition in ipairs(found) do
        for _, columns in ipairs(condition.columns) do vim.list_extend(names, columns) end
      end
      parser.request({ kind = 'quote', names = names }, function(quoted, quote_err)
        if quote_err then return answer() end
        local items, seen, n = {}, {}, 0
        for _, condition in ipairs(found) do
          local parts = {}
          for _ in ipairs(condition.columns) do
            parts[#parts + 1] = ('%s.%s = %s.%s'):format(condition.earlier, quoted.names[n + 1],
              condition.joined, quoted.names[n + 2])
            n = n + 2
          end
          local text = table.concat(parts, ' AND ')
          if not seen[text] then
            seen[text] = true
            table.insert(items, {
              label = text,
              insertText = text,
              sortText = ('%04d'):format(#items),
              labelDetails = { description = condition.fk.name },
              documentation = condition.fk.name .. ': ' .. condition.fk.description,
              kind = vim.lsp.protocol.CompletionItemKind.Reference,
            })
          end
        end
        answer(items)
      end)
    end)
  end)
end

M.new = source.new

return M
