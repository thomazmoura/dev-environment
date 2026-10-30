-- Connects the SQL Server language servers to a sql buffer's dadbod database:
-- - SqlToolsService (sqlserver_ls) with connection/connect, as VS Code's mssql extension
--   does. Without it the server only parses the text: with it, hover (gh, K) shows a column's
--   type and nullability, and gd on a table or view opens its CREATE script, which the server
--   writes to a temporary file;
-- - sqlserver-assist (sqlserver_assist, modules/sql-assist) with sqlserver/connection, a
--   SqlClient connection string, for "Expand *" and the join/INSERT completions.
-- config/sql_dialect.lua calls M.sync when it attaches the servers to a buffer, and LspAttach
-- does when one starts. The password comes from config/sqlserver_locksmith.lua, as it does
-- for dadbod's queries. It goes over each server's stdin only, and never while the LSP log
-- level is DEBUG or below, where NeoVim writes every message to lsp.log in plain text
local M = {}

local SERVERS = { 'sqlserver_ls', 'sqlserver_assist' }

-- dadbod's authentication= → SqlToolsService's authenticationType. The others (Azure AD
-- interactive...) take a token the server asks its client for: those buffers stay unconnected
local METHODS = { SqlPassword = 'SqlLogin', ActiveDirectoryPassword = 'ActiveDirectoryPassword' }

-- dadbod's encrypt= (sqlcmd's -N) → SqlToolsService's encrypt. Anything else, or none, is
-- Optional: encrypted when the server asks for it, as sqlcmd does by default
local ENCRYPT = { ['true'] = 'Mandatory', yes = 'Mandatory', mandatory = 'Mandatory', strict = 'Strict' }

-- client id → buffer → the URL it was connected to
local connected = {}

-- Whether the warning about the LSP log level was given this session
local warned_log = false

--- SqlToolsService's connection options for a sqlserver: URL, nil when it can't connect to it
local function options(url)
  local parsed = vim.fn['db#url#parse'](url)
  local params = type(parsed.params) == 'table' and parsed.params or {}
  local auth = params.authentication and METHODS[params.authentication]
    or (not params.authentication and (parsed.user and 'SqlLogin' or 'Integrated'))
  if not auth then return end
  if auth ~= 'Integrated' and not parsed.password then
    url = require('config.sqlserver_locksmith').with_password(url)
    if not url then return end
    parsed = vim.fn['db#url#parse'](url)
  end
  local database = (parsed.path or ''):gsub('^/', '')
  return {
    server = (parsed.host or 'localhost') .. (parsed.port and (',' .. parsed.port) or ''),
    database = database ~= '' and database or nil,
    user = parsed.user,
    password = parsed.password,
    authenticationType = auth,
    encrypt = ENCRYPT[(params.encrypt or ''):lower()] or 'Optional',
    trustServerCertificate = (params.trustServerCertificate or ''):match('^[1tTyY]') ~= nil,
    applicationName = 'nvim',
  }
end

--- A SqlClient connection string from SqlToolsService's options, every value quoted
local function connection_string(opts)
  local function quote(value) return '"' .. (tostring(value):gsub('"', '""')) .. '"' end
  local parts = {
    { 'Server', opts.server },
    { 'Database', opts.database },
    { 'Encrypt', opts.encrypt },
    { 'TrustServerCertificate', opts.trustServerCertificate },
    { 'Application Name', opts.applicationName },
  }
  if opts.authenticationType == 'Integrated' then
    table.insert(parts, { 'Integrated Security', true })
  else
    if opts.authenticationType == 'ActiveDirectoryPassword' then
      table.insert(parts, { 'Authentication', 'Active Directory Password' })
    end
    table.insert(parts, { 'User ID', opts.user })
    table.insert(parts, { 'Password', opts.password })
  end
  local written = {}
  for _, part in ipairs(parts) do
    if part[2] ~= nil then table.insert(written, part[1] .. '=' .. quote(part[2])) end
  end
  return table.concat(written, ';')
end

-- How each server is connected to a buffer's database, and disconnected from it
local CONNECT = {
  sqlserver_ls = function(client, buf, uri, opts, buffers)
    client:request('connection/connect', { ownerUri = uri, connection = { options = opts } }, function(err, accepted)
      if err or not accepted then
        buffers[buf] = nil
        vim.notify('SQL: connection refused by the language server' .. (err and (': ' .. err.message) or ''),
          vim.log.levels.WARN)
      end
    end, buf)
  end,
  sqlserver_assist = function(client, _, uri, opts)
    client:notify('sqlserver/connection', { textDocument = { uri = uri }, connectionString = connection_string(opts) })
  end,
}
local DISCONNECT = {
  sqlserver_ls = function(client, uri) client:notify('connection/disconnect', { ownerUri = uri }) end,
  sqlserver_assist = function(client, uri)
    client:notify('sqlserver/connection', { textDocument = { uri = uri }, connectionString = vim.NIL })
  end,
}

--- Whether NeoVim would write the messages sent, password included, to lsp.log
local function logging_messages()
  return vim.lsp.log.get_level() <= vim.log.levels.DEBUG
end

--- Connects the buffer's servers to its dadbod connection, unless they already are
function M.sync(buf)
  local url = require('config.sql_dialect').dadbod_url(buf)
  if url then
    require('lazy').load({ plugins = { 'vim-dadbod' } })
    url = vim.fn['db#resolve'](url)
    if not url:match('^sqlserver:') then url = nil end
  end
  local uri = vim.uri_from_bufnr(buf)
  -- Asked once for both servers (it may ask for the password)
  local opts
  for _, name in ipairs(SERVERS) do
    local client = vim.lsp.get_clients({ bufnr = buf, name = name })[1]
    local buffers = client and (connected[client.id] or {})
    if client and buffers[buf] ~= url then
      connected[client.id] = buffers
      if buffers[buf] then DISCONNECT[name](client, uri) end
      buffers[buf] = url
      if url and opts == nil then opts = options(url) or false end
      if opts and opts.password and logging_messages() then
        -- Asked again on the next sync, once the level is back up
        buffers[buf] = nil
        if not warned_log then
          warned_log = true
          vim.notify('SQL: not connecting the language servers while the LSP log level is DEBUG:'
            .. ' lsp.log would get the password', vim.log.levels.WARN)
        end
      elseif opts then
        CONNECT[name](client, buf, uri, opts, buffers)
      end
    end
  end
end

function M.setup()
  vim.lsp.config('sqlserver_ls', {
    handlers = {
      -- The answer to connection/connect: a login or network error lands here
      ['connection/complete'] = function(_, result, ctx)
        -- errorMessage is null (vim.NIL, truthy) on success
        if not result or type(result.errorMessage) ~= 'string' then return end
        local buffers = connected[ctx.client_id]
        if buffers then buffers[vim.uri_to_bufnr(result.ownerUri)] = nil end
        vim.notify('SQL: no metadata, the language server could not connect: ' .. result.errorMessage,
          vim.log.levels.WARN)
      end,
    },
  })

  local group = vim.api.nvim_create_augroup('SqlConnection', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and vim.list_contains(SERVERS, client.name) then M.sync(args.buf) end
    end,
  })
  -- gd on a table or view opens the CREATE script the server wrote to a temporary file:
  -- it gets the connection of the buffer gd came from (the current one while the script's is
  -- created), so its own gd, hover and <Leader>r reach the same database, as in SSMS
  vim.api.nvim_create_autocmd('BufNew', {
    group = group,
    pattern = '*/mssql_definition_*/*.sql',
    callback = function(args)
      local from = vim.api.nvim_get_current_buf()
      if from ~= args.buf and vim.bo[from].filetype == 'sql' then
        vim.b[args.buf].db = require('config.sql_dialect').dadbod_url(from)
      end
    end,
  })
  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(args)
      -- The Postgres server took the buffer over, or it was closed
      local buffers = connected[args.data.client_id]
      if not buffers or not buffers[args.buf] then return end
      buffers[args.buf] = nil
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and not client:is_stopped() and DISCONNECT[client.name] then
        DISCONNECT[client.name](client, vim.uri_from_bufnr(args.buf))
      end
    end,
  })
end

return M
