-- SQL Server and Postgres passwords for vim-dadbod, kept in locksmith.nvim (namespace
-- "dadbod", one secret per server and login). Called by autoload/sqlserver_locksmith.vim and
-- autoload/postgresql_locksmith.vim, dadbod's adapters for sqlserver: and postgresql: URLs:
-- one with a login and no password gets the saved password when the server takes it, or else
-- the one typed, saved as soon as the server takes it. A Postgres server that lets the login
-- in without one (trust, ~/.pgpass, $PGPASSWORD) is asked for none. locksmith is unlocked
-- first, asking again after a wrong password; with its prompt cancelled, the password typed is
-- used but not saved. Once per login and NeoVim: then it is kept in memory, so an existing
-- connection costs only locksmith's own password. <Leader>db (plugins/database.lua) calls
-- open_ui, which opens DBUI only once locksmith is unlocked
local M = {}

local NAMESPACE = 'dadbod'

-- How long a check may wait for the server, in ms
local CHECK_TIMEOUT = 30000

-- What each scheme needs: `check`, the command running SELECT 1 for url; `env`, the variable
-- its client reads the password from; `rejected`, its words for a refused login; `optional`,
-- a login may need no password
local SCHEMES = {
  sqlserver = {
    check = function(url)
      return vim.list_extend(vim.fn['db#adapter#sqlserver#interactive'](url), { '-Q', 'SELECT 1' })
    end,
    env = 'SQLCMDPASSWORD',
    rejected = { 'login failed' },
    -- Authentication methods that take the password. The others (integrated, Azure AD
    -- interactive...) are left to sqlcmd
    takes_password = function(parsed)
      local method = type(parsed.params) == 'table' and parsed.params.authentication or nil
      return not method or method == 'SqlPassword' or method == 'ActiveDirectoryPassword'
    end,
  },
  postgresql = {
    -- -w (from dadbod): psql never prompts, it fails with "no password supplied"
    check = function(url)
      return vim.list_extend(vim.fn['db#adapter#postgresql#interactive'](url), { '--no-psqlrc', '-c', 'SELECT 1' })
    end,
    env = 'PGPASSWORD',
    rejected = { 'password authentication failed', 'no password supplied' },
    optional = true,
  },
}

-- Secret name → the password the server took this session, or false when it needs none
local session = {}

local function notify(message, level)
  vim.notify('dadbod: ' .. message, level or vim.log.levels.INFO)
end

--- <scheme>.<host>[_<port>].<user>: locksmith names allow only letters, digits and ._-
local function secret_name(parsed)
  local server = (parsed.host or 'localhost') .. (parsed.port and ('_' .. parsed.port) or '')
  return (('%s.%s.%s'):format(parsed.scheme, server, parsed.user):gsub('[^%w._-]', '_'))
end

--- Runs fn(callback) and waits for callback(value, err): locksmith is asynchronous, dadbod's
--- adapters are not. Its prompts run while waiting
local function await(fn)
  local done, value, err = false, nil, nil
  fn(function(v, e)
    done, value, err = true, v, e
  end)
  vim.wait(10 * 60 * 1000, function()
    return done
  end, 20)
  return value, err
end

--- 'ok', 'rejected' (the server refused the login) or 'error' (anything else: the server is
--- unreachable...), from a SELECT 1 with that password, or with none when it is nil
local function check(scheme, url, password)
  local ok, result = pcall(function()
    return vim.system(scheme.check(url), { env = password and { [scheme.env] = password } or nil, text = true })
      :wait(CHECK_TIMEOUT)
  end)
  if not ok then
    return 'error'
  elseif result.code == 0 then
    return 'ok'
  end
  local output = ((result.stdout or '') .. (result.stderr or '')):lower()
  for _, words in ipairs(scheme.rejected) do
    if output:find(words, 1, true) then
      return 'rejected'
    end
  end
  return 'error'
end

local function ask(user)
  local ok, typed = pcall(vim.fn.inputsecret, ('Password for %s: '):format(user))
  vim.cmd.redraw()
  return ok and typed ~= '' and typed or nil
end

--- locksmith's questions while dadbod waits on it: vim.wait (await) runs locksmith's
--- scheduled prompts but keeps typed keys queued until it returns, so vim.ui.select's picker
--- (telescope's) never gets them and its Retry hangs. inputsecret(), input() and inputlist()
--- read the keys themselves
local function blocking_prompt(message, callback, opts)
  local ok, answer
  if opts.kind == 'choice' then
    local lines = { vim.split(message, '\n')[1] }
    for i, choice in ipairs(opts.choices) do
      table.insert(lines, ('%d. %s'):format(i, choice))
    end
    -- 0 (cancelled) is no choice for locksmith
    ok, answer = pcall(vim.fn.inputlist, lines)
  elseif opts.kind == 'password' then
    ok, answer = pcall(vim.fn.inputsecret, message)
  else
    ok, answer = pcall(vim.fn.input, { prompt = message, cancelreturn = '' })
  end
  vim.cmd.redraw()
  callback(ok and answer or nil)
end

--- locksmith, unlocked first: a wrong password offers Retry until one opens the store. nil
--- when it is missing or its prompt was cancelled: the server's password is then asked and
--- used without being saved
local function unlocked_locksmith()
  local found, locksmith = pcall(require, 'locksmith')
  if not found then
    return nil
  end
  locksmith.set_prompt(blocking_prompt)
  local ran, ok, err = pcall(await, function(callback)
    locksmith.unlock(callback)
  end)
  locksmith.set_prompt(nil)
  if not (ran and ok) then
    notify('locksmith stays locked, passwords are neither read nor saved: ' .. tostring(ran and err or ok),
      vim.log.levels.WARN)
    return nil
  end
  return locksmith
end

--- The password for url, false when the server needs none, nil when none was typed; and
--- whether the server took it
local function password_for(scheme, url, parsed, name)
  local locksmith = unlocked_locksmith()

  if locksmith then
    local saved, err = await(function(callback)
      locksmith.get(NAMESPACE, name, callback)
    end)
    if err then
      notify('no saved password: ' .. err, vim.log.levels.WARN)
    elseif saved then
      local verdict = check(scheme, url, saved)
      if verdict ~= 'rejected' then
        return saved, verdict == 'ok'
      end
      notify(('the saved password for %s was refused'):format(parsed.user), vim.log.levels.WARN)
    end
  end

  if scheme.optional then
    -- Not refused without one ('error' included: dadbod runs it and shows why)
    local verdict = check(scheme, url, nil)
    if verdict ~= 'rejected' then
      return false, verdict == 'ok'
    end
  end

  while true do
    local typed = ask(parsed.user)
    if not typed then
      return nil
    end
    local verdict = check(scheme, url, typed)
    if verdict == 'ok' and locksmith then
      local _, err = await(function(callback)
        locksmith.set(NAMESPACE, name, typed, callback)
      end)
      if err then
        notify('password not saved: ' .. err, vim.log.levels.WARN)
      end
    end
    -- Unchecked ('error'): dadbod runs it and shows why the server could not be reached
    if verdict ~= 'rejected' then
      return typed, verdict == 'ok'
    end
    notify(('login failed for %s'):format(parsed.user), vim.log.levels.WARN)
  end
end

--- url with the password filled in, url itself when it needs none, nil when none was typed
---@param url string
---@return string|nil
function M.with_password(url)
  local parsed = vim.fn['db#url#parse'](url)
  local scheme = SCHEMES[parsed.scheme]
  if not scheme or not parsed.user or parsed.password or vim.in_fast_event()
    or (scheme.takes_password and not scheme.takes_password(parsed)) then
    return url
  end

  local name = secret_name(parsed)
  local password = session[name]
  if password == nil then
    local taken
    password, taken = password_for(scheme, url, parsed, name)
    if password == nil then
      return nil
    end
    if taken then
      session[name] = password
    end
  end
  if password == false then
    return url
  end
  -- As dadbod does with the password it asks for itself
  return vim.fn.substitute(url, [[://[^:/@]*\zs@]], ':' .. vim.fn['db#url#encode'](password) .. '@', '')
end

--- DBUI in a new tab, once locksmith is unlocked: asks for its password (again, even after it
--- was declined), and opens nothing when it stays locked
function M.open_ui()
  require('locksmith').unlock(function(ok, err)
    if not ok then
      notify('database UI not opened: ' .. (err or 'locksmith is locked'), vim.log.levels.WARN)
      return
    end
    vim.cmd.tabnew()
    vim.cmd.DBUI()
  end)
end

return M
