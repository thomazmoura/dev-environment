-- dadbod's results per query buffer, set up from plugins/database.lua. dadbod shows every
-- query's result in the tab's one preview window, in a new .dbout temp file per run, and drops
-- the replaced buffer (bufhidden=delete) but not its file: this keeps, per query buffer, the
-- results it ran, newest last.
--
-- Entering a query buffer shows its result in the preview window (the newest, or the one
-- picked), or closes the window when it ran none yet; after a :pclose (or gq) it stays closed
-- until the next run. <Leader>d? in a query buffer (plugins/database.lua) or in its results
-- (after/ftplugin/dbout.lua) picks one of its results, newest first, in telescope.
--
-- A result shown again is read from its file, so dadbod's per-file BufReadPost sets its b:db
-- back (R, r, <C-c> and gq work) and config/dbout_compact.lua lays it out again. The preview
-- window is never switched away from a query still running: dadbod cancels it on BufUnload.
local M = {}

-- Query buffer → its results, oldest first: { file, query (lines), started (os.time()),
-- t0 (hrtime), duration (seconds, nil while running) }
local history = {}
-- Result file → the query buffer it belongs to
local owner = {}
-- Query buffer → the result file it shows
local current = {}
-- Set while this module closes the preview window, telling it from a :pclose
local closing = false

local QUERY_FILETYPES = { sql = true, mysql = true, plsql = true }

local function notify(message, level)
  vim.notify('dadbod: ' .. message, level or vim.log.levels.INFO)
end

--- The current tab's preview window
local function preview_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.wo[win].previewwindow then return win end
  end
end

--- The buffer of a file by its exact name (bufnr() would read it as a pattern)
local function buf_of(file)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == file then return buf end
  end
end

--- A dadbod result, by its file: vim-dadbod alone (before dadbod-ui loads) sets no filetype
local function is_result(buf)
  return vim.api.nvim_buf_get_name(buf):match('%.dbout$') ~= nil
end

local function is_query_buffer(buf)
  return QUERY_FILETYPES[vim.bo[buf].filetype] and require('config.sql_dialect').dadbod_url(buf) ~= nil
end

local function entry_of(buf, file)
  for i, entry in ipairs(history[buf] or {}) do
    if entry.file == file then return entry, i end
  end
end

--- The query dadbod ran into file, as sent (its input file, read now: for a whole saved
--- buffer that is the buffer's own file), without the blank lines a range run starts with
local function query_of(file)
  local result = buf_of(file)
  local db = result and vim.b[result].db
  local input = type(db) == 'table' and db.input
  if not input or vim.fn.filereadable(input) == 0 then return {} end
  local lines = vim.fn.readfile(input)
  while lines[1] and lines[1]:match('^%s*$') do table.remove(lines, 1) end
  return lines
end

--- Shows file in the preview window (or closes it when nil), unless the result there is a
--- query still running or the window shows something other than a result
local function show(file)
  local win = preview_win()
  if win then
    local shown = vim.api.nvim_win_get_buf(win)
    if not is_result(shown) then return end
    if file and vim.api.nvim_buf_get_name(shown) == file then return end
    local db = vim.b[shown].db
    if type(db) == 'table' and db.job then
      return notify('a query is still running in the results window (<C-c> there cancels it)',
        vim.log.levels.WARN)
    end
  end
  if file and vim.fn.filereadable(file) == 1 then
    vim.cmd('silent pedit ' .. vim.fn.fnameescape(file))
    local new = preview_win()
    if new then vim.w[new].dbout_owner = owner[file] end
  elseif win then
    closing = true
    pcall(vim.api.nvim_win_close, win, false)
    closing = false
  end
end

--- Shows the current buffer's result, when it is a query buffer and the tab follows them
local function follow()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.t.dbout_follow or not is_query_buffer(buf) then return end
  -- Not from a float (a picker's) or from the preview window itself
  if vim.api.nvim_win_get_config(0).relative ~= '' or vim.wo.previewwindow then return end
  show(current[buf])
end

--- A query starting: a new result of the current query buffer, or one run again (R in the
--- results, the same file). From the results window (dadbod's r, dadbod-ui's foreign key
--- jump), it goes to the query buffer of the result that window showed
local function started(file)
  local buf = vim.api.nvim_get_current_buf()
  if is_result(buf) then
    buf = owner[file] or vim.w.dbout_owner
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  end
  local list = history[buf] or {}
  history[buf] = list
  local entry, i = entry_of(buf, file)
  if entry then
    table.remove(list, i)
  else
    entry = { file = file, query = query_of(file) }
  end
  entry.started, entry.t0, entry.duration = os.time(), vim.uv.hrtime(), nil
  table.insert(list, entry)
  owner[file], current[buf] = buf, file
  vim.t.dbout_follow = true
  local win = preview_win()
  if win then vim.w[win].dbout_owner = buf end
end

local function finished(file)
  local buf = owner[file]
  local entry = buf and entry_of(buf, file)
  if entry then entry.duration = (vim.uv.hrtime() - entry.t0) / 1e9 end
  -- A switch skipped while it ran happens now
  vim.schedule(follow)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('DboutHistory', { clear = true })
  -- dadbod's events are User <outfile>/DBExecutePre and /DBExecutePost
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = '*DBExecutePre',
    callback = function(args) started((args.match:gsub('/DBExecutePre$', ''))) end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = '*DBExecutePost',
    callback = function(args) finished((args.match:gsub('/DBExecutePost$', ''))) end,
  })
  -- Scheduled: after the switch (:b#) is done
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function() vim.schedule(follow) end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if not closing and win and vim.api.nvim_win_is_valid(win) and vim.wo[win].previewwindow then
        local tab = vim.api.nvim_win_get_tabpage(win)
        vim.t[tab].dbout_follow = false
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      for _, entry in ipairs(history[args.buf] or {}) do owner[entry.file] = nil end
      history[args.buf], current[args.buf] = nil, nil
    end,
  })
end

local function duration_text(entry)
  if not entry.duration then return '…' end
  if entry.duration < 60 then return ('%.1fs'):format(entry.duration) end
  return ('%dm%02ds'):format(math.floor(entry.duration / 60), math.floor(entry.duration % 60))
end

local function one_line(query)
  return vim.trim((table.concat(query, ' '):gsub('%s+', ' ')))
end

--- <Leader>d?: picks one of the results of the current query buffer, or of the one the
--- current results belong to, newest first, and shows it in the preview window
function M.pick()
  local buf = vim.api.nvim_get_current_buf()
  if is_result(buf) then
    buf = owner[vim.api.nvim_buf_get_name(buf)] or vim.w.dbout_owner
  end
  local list = buf and vim.api.nvim_buf_is_valid(buf) and history[buf]
  if not list or #list == 0 then return notify('no results for this query buffer yet') end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local previewers = require('telescope.previewers')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  -- Newest first: the first entry is the one selected
  local entries = {}
  for i = #list, 1, -1 do table.insert(entries, list[i]) end

  pickers.new({}, {
    prompt_title = 'Results of ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t'),
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        local text = one_line(entry.query)
        return {
          value = entry,
          ordinal = text,
          display = ('%s %s  %6s  %s'):format(entry.file == current[buf] and '●' or ' ',
            os.date('%H:%M:%S', entry.started), duration_text(entry), text),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = 'Result',
      define_preview = function(self, item)
        local lines = vim.fn.filereadable(item.value.file) == 1 and vim.fn.readfile(item.value.file) or {}
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        require('config.dbout_compact').compact(self.state.bufnr)
        vim.wo[self.state.winid].wrap = false
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local item = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not item then return end
        current[buf] = item.value.file
        vim.t.dbout_follow = true
        show(item.value.file)
      end)
      return true
    end,
  }):find()
end

return M
