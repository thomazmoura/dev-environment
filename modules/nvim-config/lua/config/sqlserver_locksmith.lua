-- SQL Server passwords for vim-dadbod, kept in locksmith.nvim (namespace "dadbod", one secret
-- per server and login). Called by autoload/sqlserver_locksmith.vim for every sqlserver: URL:
-- one with a login and no password gets the saved password when the server takes it, or else
-- the one typed, saved as soon as the server takes it. Once per login and NeoVim: then it is
-- kept in memory, so an existing connection costs only locksmith's own password
local M = {}

local NAMESPACE = 'dadbod'

-- Authentication methods that take the password. The others (integrated, Azure AD
-- interactive...) are left to sqlcmd
local PASSWORD_METHODS = { SqlPassword = true, ActiveDirectoryPassword = true }

-- How long a check may wait for the server, in ms
local CHECK_TIMEOUT = 30000

-- Secret name → the password the server took this session
local session = {}

local function notify(message, level)
  vim.notify('dadbod: ' .. message, level or vim.log.levels.INFO)
end

--- sqlserver.<host>[_<port>].<user>: locksmith names allow only letters, digits and ._-
local function secret_name(parsed)
  local server = (parsed.host or 'localhost') .. (parsed.port and ('_' .. parsed.port) or '')
  return (('sqlserver.%s.%s'):format(server, parsed.user):gsub('[^%w._-]', '_'))
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
--- unreachable...), from a SELECT 1 with that password
local function check(url, password)
  local ok, result = pcall(function()
    local cmd = vim.fn['db#adapter#sqlserver#interactive'](url)
    vim.list_extend(cmd, { '-Q', 'SELECT 1' })
    return vim.system(cmd, { env = { SQLCMDPASSWORD = password }, text = true }):wait(CHECK_TIMEOUT)
  end)
  if not ok then
    return 'error'
  elseif result.code == 0 then
    return 'ok'
  end
  return ((result.stdout or '') .. (result.stderr or '')):lower():find('login failed', 1, true) and 'rejected'
    or 'error'
end

local function ask(user)
  local ok, typed = pcall(vim.fn.inputsecret, ('Password for %s: '):format(user))
  vim.cmd.redraw()
  return ok and typed ~= '' and typed or nil
end

--- The password for url, and whether the server took it; nil when none was typed
local function password_for(url, parsed, name)
  local found, locksmith = pcall(require, 'locksmith')
  if not found then
    locksmith = nil
  end

  if locksmith then
    local saved, err = await(function(callback)
      locksmith.get(NAMESPACE, name, callback)
    end)
    if err then
      notify('no saved password: ' .. err, vim.log.levels.WARN)
    elseif saved then
      local verdict = check(url, saved)
      if verdict ~= 'rejected' then
        return saved, verdict == 'ok'
      end
      notify(('the saved password for %s was refused'):format(parsed.user), vim.log.levels.WARN)
    end
  end

  while true do
    local typed = ask(parsed.user)
    if not typed then
      return nil
    end
    local verdict = check(url, typed)
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
  local method = type(parsed.params) == 'table' and parsed.params.authentication or nil
  if not parsed.user or parsed.password or (method and not PASSWORD_METHODS[method]) or vim.in_fast_event() then
    return url
  end

  local name = secret_name(parsed)
  local password = session[name]
  if not password then
    local taken
    password, taken = password_for(url, parsed, name)
    if not password then
      return nil
    end
    if taken then
      session[name] = password
    end
  end
  -- As dadbod does with the password it asks for itself
  return vim.fn.substitute(url, [[://[^:/@]*\zs@]], ':' .. vim.fn['db#url#encode'](password) .. '@', '')
end

return M
