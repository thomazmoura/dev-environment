-- Connects SqlToolsService (sqlserver_ls) to a sql buffer's dadbod database, as VS Code's
-- mssql extension does with connection/connect. Without it the server only parses the text:
-- with it, hover (gh, K) shows a column's type and nullability, and gd on a table or view
-- opens its CREATE script, which the server writes to a temporary file
-- config/sql_dialect.lua calls M.sync when it attaches the server to a buffer, and LspAttach
-- does when the server starts. The password comes from config/sqlserver_locksmith.lua, as it
-- does for dadbod's queries
local M = {}

local SERVER = 'sqlserver_ls'

-- dadbod's authentication= → SqlToolsService's authenticationType. The others (Azure AD
-- interactive...) take a token the server asks its client for: those buffers stay unconnected
local METHODS = { SqlPassword = 'SqlLogin', ActiveDirectoryPassword = 'ActiveDirectoryPassword' }

-- dadbod's encrypt= (sqlcmd's -N) → SqlToolsService's encrypt. Anything else, or none, is
-- Optional: encrypted when the server asks for it, as sqlcmd does by default
local ENCRYPT = { ['true'] = 'Mandatory', yes = 'Mandatory', mandatory = 'Mandatory', strict = 'Strict' }

-- client id → buffer → the URL it was connected to
local connected = {}

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

--- Connects the buffer's server to its dadbod connection, unless it already is
function M.sync(buf)
  local client = vim.lsp.get_clients({ bufnr = buf, name = SERVER })[1]
  if not client then return end
  local url = require('config.sql_dialect').dadbod_url(buf)
  if url then
    require('lazy').load({ plugins = { 'vim-dadbod' } })
    url = vim.fn['db#resolve'](url)
    if not url:match('^sqlserver:') then url = nil end
  end
  local buffers = connected[client.id] or {}
  connected[client.id] = buffers
  if buffers[buf] == url then return end

  local uri = vim.uri_from_bufnr(buf)
  if buffers[buf] then client:notify('connection/disconnect', { ownerUri = uri }) end
  buffers[buf] = url
  local opts = url and options(url)
  if not opts then return end
  client:request('connection/connect', { ownerUri = uri, connection = { options = opts } }, function(err, accepted)
    if err or not accepted then
      buffers[buf] = nil
      vim.notify('SQL: connection refused by the language server' .. (err and (': ' .. err.message) or ''),
        vim.log.levels.WARN)
    end
  end, buf)
end

function M.setup()
  vim.lsp.config(SERVER, {
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
      if client and client.name == SERVER then M.sync(args.buf) end
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
      if client and not client:is_stopped() then
        client:notify('connection/disconnect', { ownerUri = vim.uri_from_bufnr(args.buf) })
      end
    end,
  })
end

return M
