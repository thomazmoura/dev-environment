-- The app `dotnet watch` runs for a project, so <Leader>dr (config/dotnet_debug)
-- attaches to it instead of building a second copy over watch's bin/ and obj/.
-- Read from /proc: Linux only, and only processes of this machine/container.
local M = {}

local function read(path)
  local file = io.open(path, 'rb')
  if not file then return end
  local content = file:read('*a')
  file:close()
  return content
end

-- Whether the process runs target_path: `dotnet <dll>` (absolute or relative
-- to its cwd) or the apphost next to the dll
local function runs(pid, target_path, apphost)
  local proc = '/proc/' .. pid
  if vim.uv.fs_readlink(proc .. '/exe') == apphost then return true end
  local cmdline = read(proc .. '/cmdline')
  if not cmdline then return false end
  local cwd
  for _, arg in ipairs(vim.split(cmdline, '\0', { plain = true, trimempty = true })) do
    if arg == target_path then return true end
    if arg:match('%.dll$') and not vim.startswith(arg, '/') then
      cwd = cwd or vim.uv.fs_readlink(proc .. '/cwd')
      if cwd and vim.fs.normalize(vim.fs.joinpath(cwd, arg)) == target_path then return true end
    end
  end
  return false
end

-- The pid of the newest process `dotnet watch` started from target_path, the
-- project's TargetPath. DOTNET_WATCH=1 is set only in the app watch launches,
-- which leaves out watch itself, `dotnet run` and a plain run of the app.
function M.find(target_path)
  if vim.fn.has('linux') == 0 or target_path == '' then return end
  target_path = vim.fs.normalize(target_path)
  local apphost = target_path:gsub('%.dll$', '')
  local found
  for entry in vim.fs.dir('/proc') do
    local pid = tonumber(entry)
    if pid and pid ~= vim.fn.getpid() and runs(pid, target_path, apphost) then
      local environ = read('/proc/' .. pid .. '/environ')
      if environ and ('\0' .. environ):find('\0DOTNET_WATCH=1\0', 1, true) then
        found = math.max(found or 0, pid)
      end
    end
  end
  return found
end

return M
