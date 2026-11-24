-- dadbod-ui's Buffers list as the queries that ran, set up from plugins/database.lua.
-- dadbod-ui lists every query buffer it opens (New query, a table's helpers) the moment it
-- opens it, in g:db_ui_tmp_query_location, so the list fills with empty ones. Here:
--
-- - A buffer it opens is a draft instead: moved to the location's .drafts/ (which its list,
--   a glob of the folder, never sees) and taken off the list.
-- - Running (<Leader>r, <Leader>R or a selection's <Leader>r, plugins/database.lua) compares
--   the whole buffer, comments and spacing aside, with what it held when it last ran
--   without errors. When it differs and this run ends without errors too, the buffer moves
--   to a new file in the location, listed at the end of Buffers, and the file it left gets
--   back the query it ran: each different query that ran is one entry, and the buffer is
--   always the newest one. A draft's first run is its first entry. A run with errors (Msg
--   with a Level of 11 or more from sqlcmd, ERROR/FATAL from psql, or a cancelled one)
--   changes nothing, nor does an empty buffer (comments alone).
-- - A draft closed or left in NeoVim's exit with a query in it, never run, is kept as an
--   entry rather than lost; an empty one is just deleted.
--
-- An entry opened from the list (<CR>, or <Tab>'s preview, after/ftplugin/dbui.lua) last ran
-- what its file holds. autoload/dbui_buffers.vim changes dadbod-ui's list in place, and
-- points the result of a run at the file its buffer moved to, so R there runs that query.
local M = {}

-- Draft buffers (never run)
local drafts = {}
-- Query buffer → what it last ran without errors: { norm (normalized text), lines }
local last_run = {}
-- Query buffer → the query its next run is to make an entry of: { tick (changedtick), norm, lines }
local pending = {}
-- Result file of a run under way → that query, with its buffer and the buffer's file then
local running = {}

local STAMP = '%-%d%d%d%d%-%d%d%-%d%d%-%d%d%-%d%d%-%d%d$'

--- dadbod-ui's location for query buffers, or nil without one, spelled two ways: as dadbod-ui
--- expands it (its generated names, its list and its glob, and <amatch>), and with symlinks
--- resolved, as NeoVim names the buffers (~/.shared/sql-queries is a link)
local function tmp_dir()
  local location = vim.g.db_ui_tmp_query_location
  if not location or location == '' then return end
  local dir = (vim.fn.fnamemodify(location, ':p'):gsub('/$', ''))
  return dir, vim.uv.fs_realpath(dir) or dir
end

--- The file's name when it is right in the location (either spelling), not in a folder under
--- it (the drafts)
local function entry_tail(file)
  local dir, real = tmp_dir()
  if not dir then return end
  for _, prefix in ipairs({ dir .. '/', real .. '/' }) do
    if file:sub(1, #prefix) == prefix and not file:sub(#prefix + 1):find('/', 1, true) then
      return file:sub(#prefix + 1)
    end
  end
end

--- The buffer of a file by its exact name (bufnr() would read it as a pattern)
local function buf_of(file)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == file then return buf end
  end
end

--- The query without its comments (-- and nested /* */, outside quotes) and with its spacing
--- collapsed, to tell a query that changed from one that was only commented or reindented
local function normalize(lines)
  local text = table.concat(lines, '\n')
  local out, i, n = {}, 1, #text
  local function code(chunk) table.insert(out, (chunk:gsub('%s+', ' '))) end
  while i <= n do
    local s = text:find('[-/\'"]', i)
    if not s then
      code(text:sub(i))
      break
    end
    code(text:sub(i, s - 1))
    local c, two = text:sub(s, s), text:sub(s, s + 1)
    if two == '--' then
      table.insert(out, ' ')
      i = text:find('\n', s, true) or n + 1
    elseif two == '/*' then
      local depth, j = 1, s + 2
      while j <= n and depth > 0 do
        local pair = text:sub(j, j + 1)
        if pair == '/*' then depth, j = depth + 1, j + 2
        elseif pair == '*/' then depth, j = depth - 1, j + 2
        else j = j + 1 end
      end
      table.insert(out, ' ')
      i = j
    elseif c == "'" or c == '"' then
      -- A doubled quote is one inside the string
      local j = s + 1
      while j <= n do
        if text:sub(j, j) ~= c then j = j + 1
        elseif text:sub(j + 1, j + 1) == c then j = j + 2
        else break end
      end
      table.insert(out, text:sub(s, j))
      i = j + 1
    else
      table.insert(out, c)
      i = s + 1
    end
  end
  return vim.trim((table.concat(out):gsub('%s+', ' ')))
end

--- A new entry's file name: the old one's with the time now in place of its own
local function entry_name(from)
  local dir, real = tmp_dir()
  local base = vim.fn.fnamemodify(from, ':t'):gsub(STAMP, '')
  local name = ('%s-%s'):format(base, os.date('%Y-%m-%d-%H-%M-%S'))
  local candidate, i = name, 2
  while vim.uv.fs_stat(real .. '/' .. candidate) or buf_of(real .. '/' .. candidate)
    or buf_of(dir .. '/' .. candidate) do
    candidate, i = ('%s-%d'):format(name, i), i + 1
  end
  return candidate
end

--- Renames buf to file, dropping the unlisted buffer the old name is left in
local function rename(buf, file)
  local old = vim.api.nvim_buf_get_name(buf)
  vim.api.nvim_buf_set_name(buf, file)
  local left = buf_of(old)
  if left and left ~= buf and not vim.api.nvim_buf_is_loaded(left) then
    pcall(vim.api.nvim_buf_delete, left, { force = true })
  end
end

--- Changes a database's Buffers list, by the entry's name: dadbod-ui's own spelling of the
--- location goes with it, as in the names it lists and globs
local function list(action, key, name)
  local dir = tmp_dir()
  if dir then pcall(vim.fn['dbui_buffers#' .. action], key, dir .. '/' .. name) end
end

--- A buffer dadbod-ui just opened in its location, still empty on disk: made a draft
local function make_draft(buf, file)
  local _, real = tmp_dir()
  local name = entry_tail(file)
  if not real or not name or not vim.api.nvim_buf_is_valid(buf)
    or entry_tail(vim.api.nvim_buf_get_name(buf)) ~= name then return end
  local key = vim.b[buf].dbui_db_key_name
  if not key or key == '' then return end
  local draft_dir = real .. '/.drafts'
  vim.fn.mkdir(draft_dir, 'p')
  rename(buf, draft_dir .. '/' .. name)
  -- Written now, so that NeoVim reopens it in the language servers under its new name (on a
  -- write), and config/sql_connection.lua connects that: else they would answer completion
  -- and hover for a file they don't have until auto-save's first write
  vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
  -- Written before the rename (auto-save), when it opened with a table helper's query
  if vim.uv.fs_stat(real .. '/' .. name) then os.remove(real .. '/' .. name) end
  drafts[buf] = true
  list('remove', key, name)
end

--- A draft going away (closed or NeoVim's exit): kept as an entry when it holds a query
local function settle_draft(buf, listing)
  if not drafts[buf] then return end
  drafts[buf] = nil
  local _, real = tmp_dir()
  local draft = vim.api.nvim_buf_get_name(buf)
  local lines = vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    or (vim.fn.filereadable(draft) == 1 and vim.fn.readfile(draft)) or {}
  if real and normalize(lines) ~= '' then
    local name = entry_name(draft)
    vim.fn.writefile(lines, real .. '/' .. name)
    local key = vim.b[buf].dbui_db_key_name
    if listing and key then vim.schedule(function() list('add', key, name) end) end
  end
  os.remove(draft)
end

--- Before a run in buf: notes the query, when it differs from the one it last ran, for an
--- entry once it runs without errors (finished)
function M.before_run(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  pending[buf] = nil
  local _, real = tmp_dir()
  local key = vim.b[buf].dbui_db_key_name
  if not real or not key or key == '' then return end
  -- Saved queries and other files with a connection are left alone
  if not drafts[buf] and not entry_tail(vim.api.nvim_buf_get_name(buf)) then return end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local norm = normalize(lines)
  if norm == '' then return end
  local last = last_run[buf]
  if last and last.norm == norm then return end
  pending[buf] = { tick = vim.b[buf].changedtick, norm = norm, lines = lines }
end

--- A run starting (dadbod's DBExecutePre) in the current buffer: the query noted for it, if
--- the buffer has not changed since
local function started(output)
  local buf = vim.api.nvim_get_current_buf()
  local query = pending[buf]
  pending[buf] = nil
  if not query or query.tick ~= vim.b[buf].changedtick then return end
  query.buf, query.file = buf, vim.api.nvim_buf_get_name(buf)
  running[output] = query
end

--- Whether a run's result says it failed: sqlcmd's errors (Level 11 and up: 10 and below are
--- informational) and its own, psql's, a non-zero exit, or a cancel
local function failed(output)
  local result = buf_of(output)
  local db = result and vim.b[result].db
  if type(db) == 'table' and ((tonumber(db.exit_status) or 0) ~= 0 or (tonumber(db.canceled) or 0) ~= 0) then return true end
  local file = io.open(output, 'r')
  if not file then return false end
  for line in file:lines() do
    local level = line:match('^Msg %d+, Level (%d+), State %d+')
    if (level and tonumber(level) >= 11) or line:find('^Sqlcmd: Error:')
      or line:find('^psql:.-:%d+: ERROR:') or line:find('^psql:.-:%d+: FATAL:')
      or line:find('^ERROR:  ') or line:find('^FATAL:  ') or line:find('^psql: error:') then
      file:close()
      return true
    end
  end
  file:close()
  return false
end

--- A run finished (dadbod's DBExecutePost): without errors, its query is the buffer's
--- newest entry, the buffer moving to a new one when it had run another
local function finished(output)
  local query = running[output]
  running[output] = nil
  if not query or failed(output) then return end
  local buf = query.buf
  local _, real = tmp_dir()
  -- Not if it was closed or renamed meanwhile
  if not real or not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_name(buf) ~= query.file then return end
  local key = vim.b[buf].dbui_db_key_name
  local draft, last = drafts[buf], last_run[buf]
  last_run[buf] = { norm = query.norm, lines = query.lines }
  -- An entry not known to have run anything (none read from disk) is this run's
  if not draft and not last then return end

  local name = entry_name(query.file)
  local entry = real .. '/' .. name
  rename(buf, entry)
  vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
  if draft then
    drafts[buf] = nil
    os.remove(query.file)
  else
    -- The entry it left holds the query it ran
    vim.fn.writefile(last.lines, query.file)
  end
  -- A whole buffer runs from its file: R in the result runs the file it moved to
  local result = buf_of(output)
  if result then pcall(vim.fn['dbui_buffers#retarget'], result, query.file, entry) end
  list('add', key, name)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('DbuiBuffers', { clear = true })
  -- dadbod's events are User <outfile>/DBExecutePre and /DBExecutePost
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = '*DBExecutePre',
    callback = function(args) started((args.match:gsub('/DBExecutePre$', ''))) end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = '*DBExecutePost',
    -- Scheduled: out of dadbod's job callback, as the Buffers list's redraw changes windows
    callback = function(args)
      local output = args.match:gsub('/DBExecutePost$', '')
      vim.schedule(function() finished(output) end)
    end,
  })
  vim.api.nvim_create_autocmd('BufNewFile', {
    group = group,
    callback = function(args)
      if entry_tail(args.match) then
        -- Scheduled: dadbod-ui sets the buffer up (b:dbui_db_key_name, the list) after :edit
        vim.schedule(function() make_draft(args.buf, args.match) end)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufReadPost', {
    group = group,
    callback = function(args)
      if not entry_tail(args.match) then return end
      local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
      last_run[args.buf] = { norm = normalize(lines), lines = lines }
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      settle_draft(args.buf, true)
      if args.event == 'BufWipeout' then last_run[args.buf], pending[args.buf] = nil, nil end
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      for buf in pairs(vim.deepcopy(drafts)) do settle_draft(buf, false) end
    end,
  })
end

return M
