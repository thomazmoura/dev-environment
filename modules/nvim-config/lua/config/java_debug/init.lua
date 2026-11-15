-- Java debugging on nvim-dap, with the java-debug adapter that runs inside jdtls
-- (nvim-jdtls, lua/plugins/lsp.lua; modules/debugging/Install-JavaDebug.ps1). The
-- same actions as config/dotnet_debug, picked by lua/plugins/debug.lua in java buffers:
--   <Leader>dr  run the project's main class (continues a running session), with the
--               variables of the project's .env, as `docker compose` gets them
--   <Leader>dR  pick a main class, or attach to a JVM listening on localhost:5005
--               (-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005)
--   <Leader>dt  debug the test method, or the test class, under the cursor
--   <Leader>d.  repeat the last of those
--   <Leader>ds  stop (detach from an attached JVM, leaving it running)
local M = {}

local ATTACH_PORT = 5005
local last -- what <Leader>d. repeats

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Java debug' })
end

local function jdtls_client(buf)
  return vim.lsp.get_clients({ bufnr = buf or 0, name = 'jdtls' })[1]
end

-- KEY=value lines of a dotenv file: comments, blanks and `export ` skipped, one
-- level of quotes taken off. No interpolation, as docker compose's simple cases.
local function read_env(path)
  local env = {}
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return env end
  for _, line in ipairs(lines) do
    local key, value = line:match('^%s*export%s+([%w_]+)%s*=%s*(.-)%s*$')
    if not key then key, value = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$') end
    if key then
      local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
      env[key] = quoted or value:gsub('%s+#.*$', '')
    end
  end
  return env
end

-- The .env nearest the project root, looking up to the repository's root (Sentinela
-- has it next to docker-compose.yml, above backend/)
local function project_env(root)
  local found = vim.fs.find('.env', { path = root, upward = true, type = 'file',
    stop = vim.fs.dirname(vim.fs.root(root, '.git') or vim.env.HOME) })[1]
  return found and read_env(found) or {}, found
end

local function overrides(root)
  local env, file = project_env(root)
  if file then notify('Environment from ' .. vim.fn.fnamemodify(file, ':~:.')) end
  return { env = env }
end

local function save_buffers()
  vim.cmd('silent! wall')
end

local function with_client(callback)
  local client = jdtls_client()
  if not client then
    return notify('jdtls is not attached to this buffer (still starting?)', vim.log.levels.WARN)
  end
  callback(client)
end

local function attach_config()
  return {
    type = 'java',
    request = 'attach',
    name = 'Attach to localhost:' .. ATTACH_PORT,
    hostName = '127.0.0.1',
    port = ATTACH_PORT,
  }
end

local function run(config)
  last = { kind = 'config', config = config }
  require('dap').run(config)
end

-- The project's main classes as launch configurations, through jdtls
local function main_configs(client, callback)
  require('jdtls.dap').fetch_main_configs({ config_overrides = overrides(client.config.root_dir) }, function(configs)
    vim.schedule(function() callback(configs) end)
  end)
end

local function pick(items, prompt)
  vim.ui.select(items, { prompt = prompt, format_item = function(config) return config.name end }, function(config)
    if config then run(config) end
  end)
end

function M.debug_current()
  local dap = require('dap')
  if dap.session() then return dap.continue() end
  with_client(function(client)
    save_buffers()
    main_configs(client, function(configs)
      if #configs == 0 then return notify('No main class in ' .. client.config.root_dir, vim.log.levels.WARN) end
      if #configs == 1 then return run(configs[1]) end
      pick(configs, 'Debug main class')
    end)
  end)
end

function M.debug_pick()
  local client = jdtls_client()
  if not client then return run(attach_config()) end
  save_buffers()
  main_configs(client, function(configs)
    table.insert(configs, attach_config())
    pick(configs, 'Debug')
  end)
end

local function debug_test_at(buf, lnum)
  with_client(function(client)
    save_buffers()
    local opts = { bufnr = buf, lnum = lnum, config_overrides = overrides(client.config.root_dir) }
    -- Inside a method, that test; elsewhere (the class line, between methods), the class
    local inside_method = false
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { lnum - 1, 0 } })
    while ok and node do
      if node:type() == 'method_declaration' then inside_method = true break end
      node = node:parent()
    end
    local jdtls_dap = require('jdtls.dap')
    if inside_method then jdtls_dap.test_nearest_method(opts) else jdtls_dap.test_class(opts) end
    last = { kind = 'test', buf = buf, lnum = lnum }
  end)
end

function M.debug_test()
  debug_test_at(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1])
end

function M.repeat_last()
  if not last then return notify('Nothing debugged yet', vim.log.levels.WARN) end
  if last.kind == 'config' then
    save_buffers()
    return require('dap').run(last.config)
  end
  if not vim.api.nvim_buf_is_valid(last.buf) then return notify('The last test\'s buffer is gone', vim.log.levels.WARN) end
  vim.api.nvim_buf_call(last.buf, function() debug_test_at(last.buf, last.lnum) end)
end

-- An attached JVM (a container's) keeps running
function M.stop()
  local dap = require('dap')
  local session = dap.session()
  if not session then return end
  if session.config.request == 'attach' then
    dap.disconnect({ terminateDebuggee = false })
  else
    dap.terminate()
  end
end

return M
