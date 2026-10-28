-- Keeps the header of SQL Server results (and the line under it) at the top of the window
-- while its rows scroll under it, as workhorse.nvim does with a build log's header. Loaded by
-- after/ftplugin/dbout.lua.
--
-- Once a result's header is scrolled away, a float over the window's first rows shows the
-- same buffer at that header: its │ and ┼ (config/dbout_compact.lua) come along, and it
-- follows the window's horizontal scroll and wrapping. The cursor is kept off the rows it
-- covers: moving up into them scrolls the window, scrolling it moves the cursor down.
local M = {}

-- Results window → the float pinned over it
local pinned = {}
-- Results window → its topline when last pinned, telling a scroll from a cursor motion
local tops = {}

local function close(win)
  local float = pinned[win]
  pinned[win] = nil
  if float and vim.api.nvim_win_is_valid(float) then vim.api.nvim_win_close(float, true) end
end

--- The header line of the result at the top of win, when it is scrolled away, and the window's info
local function scrolled_header(win)
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype ~= 'dbout' then return nil end
  local info = vim.fn.getwininfo(win)[1]
  local header = require('config.dbout_compact').result_at(buf, info.topline)
  if header and header < info.topline then return header, info end
end

--- Pins the header of the result at the top of win over it, or drops the float when there is none
local function pin(win)
  local header, info = scrolled_header(win)
  tops[win] = vim.fn.getwininfo(win)[1].topline
  -- The header and the dash line, as many screen rows as the window wraps them in
  local height = header and vim.api.nvim_win_text_height(win, { start_row = header - 1, end_row = header }).all
  -- Tiny windows keep their rows visible
  if not header or info.height <= height + 1 then return close(win) end

  local config = {
    relative = 'win',
    win = win,
    row = 0,
    col = 0,
    width = info.width,
    height = height,
    focusable = false,
    zindex = 20,
  }
  local float = pinned[win]
  if float and vim.api.nvim_win_is_valid(float) then
    vim.api.nvim_win_set_config(float, config)
  else
    config.style = 'minimal'
    config.noautocmd = true
    float = vim.api.nvim_open_win(info.bufnr, false, config)
    -- dadbod-ui folds each result: the float shows lines, not folds
    vim.wo[float].foldenable = false
    vim.wo[float].winhighlight = 'NormalFloat:Normal'
    -- Opaque even with a global 'winblend': the rows behind must not show through
    vim.wo[float].winblend = 0
    pinned[win] = float
  end
  -- A blank gutter as wide as the window's, so the columns line up with the rows'
  vim.wo[float].number = info.textoff > 0
  vim.wo[float].numberwidth = math.min(math.max(info.textoff, 1), 20)
  vim.wo[float].statuscolumn = (' '):rep(info.textoff)
  for _, option in ipairs({ 'wrap', 'linebreak', 'breakindent' }) do
    vim.wo[float][option] = vim.wo[win][option]
  end

  local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
  vim.api.nvim_win_call(float, function()
    vim.fn.winrestview({ topline = header, lnum = header, col = 0, leftcol = leftcol })
  end)
end

--- Pins the headers of the current tab's results windows, and drops the floats of the others
local function sync()
  for win in pairs(pinned) do
    if not vim.api.nvim_win_is_valid(win) then close(win) end
  end
  for win in pairs(tops) do
    if not vim.api.nvim_win_is_valid(win) then tops[win] = nil end
  end
  local current = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      current[win] = true
      pin(win)
    end
  end
  for win in pairs(pinned) do
    if not current[win] then close(win) end
  end
end

--- Keeps the cursor of win off the rows its float covers: scroll brings the window down to
--- the cursor (moving up with k), otherwise the cursor moves down into view (<C-e>, the wheel)
local function uncover(win, scroll)
  vim.api.nvim_win_call(win, function()
    -- One screen row at a time, so wrapped lines count right. The rows above the cursor's
    -- line are counted from the text: winline() is only updated by a redraw
    for _ = 1, vim.api.nvim_win_get_height(win) do
      -- Up to date first: CursorMoved comes ahead of the redraw (gg leaves the float of the
      -- rows it jumped from until then)
      pin(win)
      local float = pinned[win]
      if not (float and vim.api.nvim_win_is_valid(float)) then return end
      local view = vim.fn.winsaveview()
      local above = view.lnum > view.topline
        and vim.api.nvim_win_text_height(win, { start_row = view.topline - 1, end_row = view.lnum - 2 }).all - view.topfill
        or 0
      if above >= vim.api.nvim_win_get_height(float) then return end
      vim.cmd(scroll and 'normal! \25' or 'normal! gj')
      if vim.deep_equal(view, vim.fn.winsaveview()) then return end
    end
  end)
end

local group = vim.api.nvim_create_augroup('DboutPin', { clear = true })
vim.api.nvim_create_autocmd({ 'WinScrolled', 'WinResized' }, {
  group = group,
  callback = function()
    sync()
    for win in pairs(pinned) do uncover(win, false) end
  end,
})
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufWinLeave', 'WinClosed', 'TabEnter', 'BufReadPost' }, {
  group = group,
  callback = function() vim.schedule(sync) end,
})
vim.api.nvim_create_autocmd('CursorMoved', {
  group = group,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    -- CursorMoved comes ahead of WinScrolled: a cursor pushed by <C-e> is a scroll down
    if pinned[win] then uncover(win, vim.fn.line('w0') == tops[win]) end
  end,
})

M.sync = sync

return M
