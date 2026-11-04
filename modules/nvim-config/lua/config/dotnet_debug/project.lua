-- .NET projects for <Leader>dr and <Leader>dR (config/dotnet_debug): the csproj
-- a buffer belongs to, the runnable ones under a directory, their msbuild
-- properties, the build (errors to the quickfix list) and the launch profile
-- from Properties/launchSettings.json, as `dotnet run` would use it.
local M = {}

-- English, uncoloured, line-by-line output whatever the machine's settings
local ENV = { DOTNET_CLI_UI_LANGUAGE = 'en', MSBUILDTERMINALLOGGER = 'off', DOTNET_NOLOGO = '1' }

-- The files a build reads, saved before Roslyn or dotnet build reads the disk
local SOURCE_EXTENSIONS = { cs = true, razor = true, cshtml = true, csproj = true, props = true, targets = true }

local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, '\n') or nil
end

function M.name(csproj) return vim.fn.fnamemodify(csproj, ':t:r') end

function M.save_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].modified and vim.bo[buf].buftype == '' and name ~= ''
      and SOURCE_EXTENSIONS[vim.fn.fnamemodify(name, ':e')] then
      vim.api.nvim_buf_call(buf, function() vim.cmd('silent update') end)
    end
  end
end

-- The nearest csproj above the buffer's file (any file of the project)
function M.for_buffer(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or vim.bo[buf].buftype ~= '' or name:find('://', 1, true) then return end
  local root = vim.fs.root(buf, function(entry) return entry:match('%.csproj$') ~= nil end)
  return root and vim.fn.glob(root .. '/*.csproj', false, true)[1]
end

local function all_projects(dir)
  if vim.fn.executable('fd') == 1 then
    -- fd honours .gitignore, as telescope's find_files does
    local out = vim.system({ 'fd', '--type', 'file', '--extension', 'csproj', '--absolute-path', '.', dir },
      { text = true }):wait()
    return vim.split(vim.trim(out.stdout or ''), '\n', { trimempty = true })
  end
  return vim.fs.find(function(entry) return entry:match('%.csproj$') ~= nil end,
    { path = dir, type = 'file', limit = math.huge })
end

-- Read from the csproj's text, not msbuild (a second per project): an
-- OutputType that only Directory.Build.props sets is missed
local function runnable(csproj)
  local text = (read(csproj) or ''):lower()
  if text:find('microsoft.net.test.sdk', 1, true) or text:match('<istestproject>%s*true') then return false end
  local tfms = text:match('<targetframeworks?>(.-)</targetframeworks?>')
  if tfms and vim.fn.has('win32') == 0 then
    local windows_only = true
    for _, tfm in ipairs(vim.split(tfms, ';', { trimempty = true })) do
      if not tfm:find('-windows', 1, true) then windows_only = false end
    end
    if windows_only then return false end
  end
  return text:match('<outputtype>%s*w?i?n?exe%s*</outputtype>') ~= nil
    or text:match('sdk="microsoft%.net%.sdk%.web"') ~= nil
    or text:match('sdk="microsoft%.net%.sdk%.worker"') ~= nil
end

-- The projects under dir that start a process (not libraries or tests)
function M.runnable(dir)
  local projects = vim.tbl_filter(runnable, all_projects(dir))
  table.sort(projects)
  return projects
end

local PROPERTIES = { 'TargetPath', 'OutputType', 'IsTestProject', 'TargetFramework', 'TargetFrameworks' }

-- callback(properties) or callback(nil, error): msbuild's evaluation, so the
-- paths are the real ones (RID folders, custom OutputPath)
function M.properties(csproj, tfm, callback)
  local cmd = { 'dotnet', 'msbuild', csproj, '-nologo' }
  for _, property in ipairs(PROPERTIES) do table.insert(cmd, '-getProperty:' .. property) end
  if tfm then table.insert(cmd, '-p:TargetFramework=' .. tfm) end
  vim.system(cmd, { text = true, env = ENV }, vim.schedule_wrap(function(out)
    local ok, decoded = pcall(vim.json.decode, (out.stdout or ''):match('%b{}') or '')
    if out.code ~= 0 or not ok or type(decoded) ~= 'table' or type(decoded.Properties) ~= 'table' then
      return callback(nil, 'msbuild could not evaluate ' .. M.name(csproj) .. ':\n'
        .. vim.trim((out.stdout or '') .. (out.stderr or '')))
    end
    local properties = {}
    for _, property in ipairs(PROPERTIES) do properties[property] = decoded.Properties[property] or '' end
    callback(properties)
  end))
end

local ERROR_FORMAT = '%f(%l\\,%c): %trror %m,%f : %trror %m'

-- callback(true) or callback(false, message); the errors go to quickfix
function M.build(csproj, tfm, callback)
  local cmd = { 'dotnet', 'build', csproj, '-nologo', '-p:GenerateFullPaths=true', '-consoleLoggerParameters:NoSummary' }
  if tfm then vim.list_extend(cmd, { '-f', tfm }) end
  vim.system(cmd, { text = true, env = ENV }, vim.schedule_wrap(function(out)
    if out.code == 0 then return callback(true) end
    local output = (out.stdout or '') .. '\n' .. (out.stderr or '')
    local errors, seen = {}, {}
    for line in vim.gsplit(output, '\n') do
      if line:find(': error ', 1, true) then
        line = vim.trim((line:gsub('%s*%[[^%]]*%]%s*$', ''))) -- the trailing [project.csproj]
        if not seen[line] then
          seen[line] = true
          table.insert(errors, line)
        end
      end
    end
    if #errors == 0 then
      local lines = vim.split(vim.trim(output), '\n')
      return callback(false, table.concat(vim.list_slice(lines, math.max(1, #lines - 15)), '\n'))
    end
    vim.fn.setqflist({}, ' ', { title = 'dotnet build ' .. M.name(csproj), lines = errors, efm = ERROR_FORMAT })
    if not pcall(vim.cmd, 'Trouble qflist open') then vim.cmd('botright copen') end
    callback(false, #errors .. ' build error(s), in the quickfix list')
  end))
end

-- commandLineArgs as the shell would split them (double quotes only)
local function split_args(line)
  local args, i = {}, 1
  if type(line) ~= 'string' then return args end
  while i <= #line do
    local char = line:sub(i, i)
    if char:match('%s') then
      i = i + 1
    elseif char == '"' then
      local close = line:find('"', i + 1, true) or #line + 1
      table.insert(args, line:sub(i + 1, close - 1))
      i = close + 1
    else
      local space = line:find('%s', i) or #line + 1
      table.insert(args, line:sub(i, space - 1))
      i = space
    end
  end
  return args
end

-- The first "Project" profile of launchSettings.json, as `dotnet run` takes
-- it: { name, env, args }, empty without one. Without it a web project runs
-- as Production, with no appsettings.Development.json and on port 5000.
function M.launch_settings(csproj)
  local path = vim.fs.dirname(csproj) .. '/Properties/launchSettings.json'
  local text = read(path)
  if not text then return { env = {}, args = {} } end
  -- JSON with comments; only whole-line ones, a URL holds "//" too
  text = text:gsub('\n%s*//[^\n]*', '\n')
  local ok, settings = pcall(vim.json.decode, text)
  if not ok or type(settings) ~= 'table' or type(settings.profiles) ~= 'table' then
    vim.notify('Could not read ' .. path, vim.log.levels.WARN, { title = '.NET debug' })
    return { env = {}, args = {} }
  end

  -- Lua tables lose the file's order: "first" is the earliest in the text
  local chosen, at
  for name, profile in pairs(settings.profiles) do
    if type(profile) == 'table' and profile.commandName == 'Project' then
      local position = text:find('"' .. name .. '"', 1, true) or math.huge
      if not at or position < at then chosen, at = name, position end
    end
  end
  if not chosen then return { env = {}, args = {} } end

  local profile = settings.profiles[chosen]
  local env = { DOTNET_LAUNCH_PROFILE = chosen }
  if type(profile.environmentVariables) == 'table' then
    for key, value in pairs(profile.environmentVariables) do env[key] = tostring(value) end
  end
  if type(profile.applicationUrl) == 'string' and not env.ASPNETCORE_URLS then
    env.ASPNETCORE_URLS = profile.applicationUrl
  end
  return { name = chosen, env = env, args = split_args(profile.commandLineArgs) }
end

return M
