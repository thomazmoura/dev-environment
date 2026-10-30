-- Which SQL language servers a sql buffer gets: SQL Server's (SqlToolsService and
-- our sqlserver-assist) or Postgres's (postgres-language-server). All claim the sql
-- filetype, so they are configured in plugins/lsp.lua but left out of vim.lsp.enable,
-- and started here.
--
-- A buffer's dialect comes from, in order:
--   1. a pin: :SqlDialect sqlserver|postgres, <Leader>dm / <Leader>dp
--   2. its dadbod connection (b:db, then w:, t:, g:db), as DBUI query buffers have
--   3. its text: T-SQL or Postgres-only syntax (GO, [names], @vars / ::casts, $$, RETURNING)
--   4. DEFAULT
-- 3 and 4 are re-checked on InsertLeave and write. :SqlDialect auto (<Leader>da)
-- drops the pin. The lualine shows the dialect, with a "?" when it is the default.
local M = {}

local DEFAULT = 'sqlserver'

local SERVERS = { sqlserver = { 'sqlserver_ls', 'sqlserver_assist' }, postgres = { 'postgres_lsp' } }
local NAMES = { sqlserver = 'SQL Server', postgres = 'Postgres' }
local SCHEMES = { sqlserver = 'sqlserver', postgres = 'postgres', postgresql = 'postgres' }

-- How many lines the text check reads
local MAX_LINES = 1000

-- Syntax only one of the two accepts, one point per line that has it
local MARKERS = {
  sqlserver = {
    [=[^\s*go\s*\d*\s*$]=],                  -- batch separator
    [=[\[[a-z_][a-z0-9_ ]*\]]=],             -- [bracketed] names
    [=[(^|[^a-z0-9_.])\@\@?[a-z_]]=],        -- @variables, @@ROWCOUNT (not e-mails)
    [=[<top\s*\(?\s*\d]=],
    [=[<(nvarchar|nchar|uniqueidentifier|datetime2?|smalldatetime|tinyint|money)>]=],
    [=[<identity\s*\(]=],
    [=[<(getdate|getutcdate|sysdatetime|isnull|dateadd|datediff|newid|scope_identity|object_id|len|charindex|try_cast|try_convert)\s*\(]=],
    [=[<(dbo|sys)\.]=],
    [=[<(nolock|raiserror)>]=],
    [=[<set\s+nocount>]=],
    [=[<begin\s+tran>]=],
    [=[<exec\s]=],
    [=[<print\s]=],
    [=[<output\s+(inserted|deleted)>]=],
    [=[<(cross|outer)\s+apply>]=],
    [=[<create\s+or\s+alter>]=],
    [=[<offset\s+\d+\s+rows>]=],
  },
  postgres = {
    [=[::\s*[a-z_]]=],                       -- ::casts
    [=[\$[a-z_]*\$]=],                       -- $$ bodies
    [=[<(returning|ilike|lateral)>]=],
    [=[<(small|big)?serial>]=],
    [=[<(jsonb|timestamptz|boolean|regclass)>]=],
    [=[<timestamp\s+with(out)?\s+time\s+zone>]=],
    [=[<language\s+'?plpgsql>]=],
    [=[<limit\s+\d]=],
    [=[<on\s+conflict>]=],
    [=[<create\s+or\s+replace>]=],
    [=[<(generate_series|unnest|now)\s*\(]=],
    [=[<interval\s+']=],
    [=[<distinct\s+on\s*\(]=],
    [=[<array\s*\[]=],
    [=[<nulls\s+(first|last)>]=],
    [=[<pg_[a-z_]+]=],
  },
}
for dialect, patterns in pairs(MARKERS) do
  MARKERS[dialect] = vim.tbl_map(function(p) return vim.regex([[\v\c]] .. p) end, patterns)
end

--- The buffer's dadbod connection (b:db, then w:, t:, g:db), as written there
function M.dadbod_url(buf)
  local db = vim.b[buf].db
  if db == nil then
    local win = vim.fn.bufwinid(buf)
    db = (win ~= -1 and vim.w[win].db) or vim.t.db or vim.g.db
  end
  if type(db) == 'table' then db = db.db_url end
  if type(db) == 'string' then return db end
end

--- The dialect of the buffer's dadbod connection, if it is one of the two
local function from_dadbod(buf)
  local db = M.dadbod_url(buf)
  return db and SCHEMES[db:match('^(%w+):')]
end

--- The dialect whose syntax the buffer has more lines of, nil on a tie
local function from_text(buf)
  local scores = { sqlserver = 0, postgres = 0 }
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, MAX_LINES, false)) do
    if not line:match('^%s*%-%-') then
      for dialect, regexes in pairs(MARKERS) do
        for _, regex in ipairs(regexes) do
          if regex:match_str(line) then scores[dialect] = scores[dialect] + 1 end
        end
      end
    end
  end
  if scores.sqlserver > scores.postgres then return 'sqlserver' end
  if scores.postgres > scores.sqlserver then return 'postgres' end
end

--- dialect, source ('pinned', 'dadbod', 'text' or 'default')
local function decide(buf)
  local b = vim.b[buf]
  if b.sql_dialect_source == 'pinned' then return b.sql_dialect, 'pinned' end
  local dialect = from_dadbod(buf)
  if dialect then return dialect, 'dadbod' end
  dialect = from_text(buf)
  if dialect then return dialect, 'text' end
  -- A tie keeps what the buffer had: an edit without markers changes nothing
  if b.sql_dialect then return b.sql_dialect, b.sql_dialect_source end
  return DEFAULT, 'default'
end

--- Detaches the other dialect's servers and starts (or reuses) this one's
local function attach(buf, dialect)
  for other, names in pairs(SERVERS) do
    if other ~= dialect then
      for _, name in ipairs(names) do
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, name = name })) do
          vim.lsp.buf_detach_client(buf, client.id)
        end
      end
    end
  end
  for _, name in ipairs(SERVERS[dialect]) do
    if #vim.lsp.get_clients({ bufnr = buf, name = name }) == 0 then
      local config = vim.deepcopy(vim.lsp.config[name])
      local function start(root)
        config.root_dir = root
        if vim.api.nvim_buf_is_valid(buf) then vim.lsp.start(config, { bufnr = buf }) end
      end
      if type(config.root_dir) == 'function' then
        config.root_dir(buf, start)
      else
        start(config.root_dir)
      end
    end
  end
end

--- Decides the buffer's dialect again and attaches its server
function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then return end
  local before = vim.b[buf].sql_dialect
  local dialect, source = decide(buf)
  vim.b[buf].sql_dialect, vim.b[buf].sql_dialect_source = dialect, source
  attach(buf, dialect)
  -- An attached server gets a connection set since; a starting one gets it on LspAttach
  if dialect == 'sqlserver' then require('config.sql_connection').sync(buf) end
  if before and before ~= dialect then
    vim.notify('SQL: ' .. NAMES[dialect] .. ' (' .. source .. ')', vim.log.levels.INFO)
  end
end

--- Pins the buffer to a dialect, or back to automatic with 'auto'
function M.set(dialect, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if dialect == 'auto' then
    vim.b[buf].sql_dialect, vim.b[buf].sql_dialect_source = nil, nil
  elseif SERVERS[dialect] then
    vim.b[buf].sql_dialect, vim.b[buf].sql_dialect_source = dialect, 'pinned'
  else
    return vim.notify('SQL: unknown dialect ' .. dialect, vim.log.levels.ERROR)
  end
  M.refresh(buf)
  vim.cmd.redrawstatus()
end

--- For the status line: the dialect, with a "?" when nothing chose it
function M.statusline()
  local b = vim.b
  if vim.bo.filetype ~= 'sql' or not b.sql_dialect then return '' end
  return NAMES[b.sql_dialect] .. (b.sql_dialect_source == 'default' and '?' or '')
end

function M.setup()
  -- A server still checking the text when the buffer switched away from it
  -- publishes afterwards: only an attached server's diagnostics are shown
  for _, names in pairs(SERVERS) do
    for _, name in ipairs(names) do
      vim.lsp.config(name, {
        handlers = {
          ['textDocument/publishDiagnostics'] = function(err, result, ctx)
            local client = vim.lsp.get_client_by_id(ctx.client_id)
            local buf = vim.uri_to_bufnr(result.uri)
            if client and client.attached_buffers[buf] then
              vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx)
            end
          end,
        },
      })
    end
  end

  require('config.sql_connection').setup()

  local group = vim.api.nvim_create_augroup('SqlDialect', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'sql',
    callback = function(args)
      local buf = args.buf
      -- Scheduled: DBUI sets b:db right after the edit that fires this
      vim.schedule(function() M.refresh(buf) end)

      vim.api.nvim_clear_autocmds({ group = group, buffer = buf })
      vim.api.nvim_create_autocmd({ 'InsertLeave', 'BufWritePost' }, {
        group = group,
        buffer = buf,
        callback = function()
          local source = vim.b[buf].sql_dialect_source
          if source == 'text' or source == 'default' then M.refresh(buf) end
        end,
      })

      local function map(lhs, dialect, desc)
        vim.keymap.set('n', lhs, function() M.set(dialect, buf) end, { buffer = buf, desc = desc })
      end
      map('<Leader>dm', 'sqlserver', 'SQL: SQL Server')
      map('<Leader>dp', 'postgres', 'SQL: Postgres')
      map('<Leader>da', 'auto', 'SQL: dialect from connection/text')
    end,
  })

  vim.api.nvim_create_user_command('SqlDialect', function(opts)
    if opts.args == '' then
      local b = vim.b
      return print(b.sql_dialect and (NAMES[b.sql_dialect] .. ' (' .. b.sql_dialect_source .. ')')
        or 'Not a sql buffer')
    end
    M.set(opts.args)
  end, {
    nargs = '?',
    complete = function() return { 'sqlserver', 'postgres', 'auto' } end,
    desc = 'Show or set the SQL dialect (language server) of the buffer',
  })
end

return M
