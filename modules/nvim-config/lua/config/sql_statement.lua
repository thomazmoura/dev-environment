-- The statement under the cursor in a sql buffer, run alone through dadbod (<Leader>r in
-- lua/plugins/database.lua), like the mssql/pgsql extensions' runCurrentStatement in VS Code.
--
-- Where a statement starts and ends comes from the buffer's dialect (config/sql_dialect.lua):
-- ScriptDom's parse for SQL Server (sqlserver-assist's sqlserver/statements, from
-- modules/sql-assist), psql's rules for Postgres (config/sql_split_postgres.lua). So a query
-- with blank lines inside runs whole, and two on one line run apart. Between two statements,
-- the cursor gets the one above, or on a comment line the one below, which the comment
-- usually is about.
local M = {}

local ns = vim.api.nvim_create_namespace('sql_statement')

--- callback({{start, end}, ...}) with byte offsets, the end excluded, or callback(nil, error),
--- given the buffer's text, its lines' start offsets and the cursor's (row, col)
local SPLITTERS = {
  sqlserver = function(buf, lines, starts, row, col, callback)
    local client = vim.lsp.get_clients({ bufnr = buf, name = 'sqlserver_assist' })[1]
    if not client then return callback(nil, 'sqlserver-assist is not running for this buffer (:checkhealth vim.lsp)') end
    local position = { line = row - 1, character = vim.str_utfindex(lines[row], 'utf-16', col, false) }
    client:request('sqlserver/statements', { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = position },
      function(err, ranges)
        if err then return callback(nil, err.message) end
        local function offset(p)
          local line = lines[p.line + 1] or ''
          return starts[p.line + 1] + vim.str_byteindex(line, 'utf-16', math.min(p.character, vim.str_utfindex(line, 'utf-16')), false)
        end
        callback(vim.tbl_map(function(r) return { offset(r.start), offset(r['end']) } end, ranges))
      end, buf)
  end,
  postgres = function(_, lines, _, _, _, callback)
    callback(require('config.sql_split_postgres').split(table.concat(lines, '\n')))
  end,
}

--- The statement holding `cursor`, else the one next to it (see the top)
local function pick(statements, cursor, line)
  local before, after
  for _, statement in ipairs(statements) do
    if statement[1] <= cursor and cursor < statement[2] then return statement end
    if statement[2] <= cursor then
      before = statement
    elseif not after then
      after = statement
    end
  end
  if line:match('^%s*%-%-') or line:match('^%s*/%*') then return after or before end
  return before or after
end

--- Row (1-based) and column (0-based) of a byte offset, from the lines' start offsets
local function position(starts, offset)
  local row = 1
  while starts[row + 1] and starts[row + 1] <= offset do row = row + 1 end
  return row, offset - starts[row]
end

function M.run()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, '\n')
  local starts, offset = {}, 0
  for i, line in ipairs(lines) do
    starts[i] = offset
    offset = offset + #line + 1
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local cursor = starts[row] + col
  local tick = vim.b[buf].changedtick

  SPLITTERS[vim.b[buf].sql_dialect or 'sqlserver'](buf, lines, starts, row, col, function(statements, err)
    if err then return vim.notify('Run statement: ' .. err, vim.log.levels.ERROR) end
    if vim.api.nvim_get_current_buf() ~= buf or vim.b[buf].changedtick ~= tick then
      return vim.notify('Run statement: the buffer changed while it was parsed', vim.log.levels.WARN)
    end
    local statement = pick(statements, cursor, lines[row])
    if not statement then return vim.notify('No statement to run', vim.log.levels.WARN) end

    -- The ] mark goes on the first byte of the statement's last character
    local last = statement[2] - 1
    while last > statement[1] and text:byte(last + 1) >= 0x80 and text:byte(last + 1) < 0xC0 do last = last - 1 end
    local first_row, first_col = position(starts, statement[1])
    local last_row, last_col = position(starts, last)

    -- A flash of what was sent, since nothing else shows where the statement was cut
    vim.hl.range(buf, ns, 'IncSearch', { first_row - 1, first_col }, { last_row - 1, last_col },
      { inclusive = true, timeout = 300 })
    -- dadbod's own characterwise run (what its g@ operator does): from the [ mark to the ]
    -- one. Loaded first: lazy.nvim's stand-in :DB runs the real one with the range's 0
    -- dropped, which sends the first line alone
    require('lazy').load({ plugins = { 'vim-dadbod' } })
    vim.api.nvim_buf_set_mark(buf, '[', first_row, first_col, {})
    vim.api.nvim_buf_set_mark(buf, ']', last_row, last_col, {})
    vim.cmd('0,1DB')
  end)
end

return M
