-- Zoom the current window, like tmux's prefix+z, to read panes that are usually
-- too small (dap-ui's Scopes, Watches, Stacks...). Both show the same buffer, so
-- its buffer-local keys (dap-ui's <CR> to expand, e to edit) work while zoomed:
--   <Leader>z - a float over 90% of the screen, rounded like gH's popup. It
--               closes on <Leader>z, :q, or as soon as another window is
--               entered, so it can't be forgotten
--   <Leader>Z - a tab with the buffer as its only window, for working in it a
--               while (gd, splits, Telescope). The tabline is hidden meanwhile
-- Either key, while zoomed in either way, zooms back out, handing the cursor
-- back to the original window.
local M = {}

local augroup = vim.api.nvim_create_augroup('Zoom', { clear = true })

-- The zoomed window's buffer and cursor go back to the window it came from
local function return_to(origin, zoomed)
  if not vim.api.nvim_win_is_valid(origin) then return end
  if vim.api.nvim_win_is_valid(zoomed)
    and vim.api.nvim_win_get_buf(zoomed) == vim.api.nvim_win_get_buf(origin) then
    local view = vim.api.nvim_win_call(zoomed, vim.fn.winsaveview)
    vim.api.nvim_win_call(origin, function() vim.fn.winrestview(view) end)
  end
  vim.api.nvim_set_current_win(origin)
end

-- Float -------------------------------------------------------------------

local function close_float(win)
  local origin = vim.w[win].zoom_origin
  return_to(origin, win)
  pcall(vim.api.nvim_win_close, win, false)
end

local function open_float()
  local origin = vim.api.nvim_get_current_win()
  local view = vim.fn.winsaveview()
  local columns, lines = vim.o.columns - 2, vim.o.lines - vim.o.cmdheight - 2
  local width, height = math.floor(columns * 0.9), math.floor(lines * 0.9)
  local name = vim.fn.bufname()
  local title = name ~= '' and vim.fn.fnamemodify(name, ':t') or '[No Name]'

  -- Not style = 'minimal': the float keeps the window's options, as a split would
  local win = vim.api.nvim_open_win(0, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((lines - height) / 2),
    col = math.floor((columns - width) / 2),
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })
  vim.w[win].zoom_origin = origin
  vim.fn.winrestview(view)

  -- Leaving it (C-h/j/k/l, a Telescope picker, gH's popup) zooms back out
  vim.api.nvim_create_autocmd('WinLeave', {
    group = augroup,
    callback = function()
      if vim.api.nvim_get_current_win() ~= win then return end
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, false) end
      end)
      return true
    end,
  })
end

-- Tab ---------------------------------------------------------------------

local saved_showtabline

local function close_tab()
  local zoomed = vim.api.nvim_get_current_win()
  local origin = vim.t.zoom_origin
  return_to(origin, zoomed)
  pcall(vim.api.nvim_win_close, zoomed, false)
end

local function open_tab()
  local origin = vim.api.nvim_get_current_win()
  vim.cmd('tab split')
  vim.t.zoom_origin = origin
  if not saved_showtabline then
    saved_showtabline = vim.o.showtabline
    vim.o.showtabline = 0
  end
end

-- However the zoom tab goes away (<Leader>Z, :q, :tabclose), the tabline returns
vim.api.nvim_create_autocmd('TabClosed', {
  group = augroup,
  callback = function()
    if not saved_showtabline then return end
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if vim.t[tab].zoom_origin then return end
    end
    vim.o.showtabline = saved_showtabline
    saved_showtabline = nil
  end,
})

-- Toggles -----------------------------------------------------------------

-- Zooms out when zoomed in either way; returns whether it did
local function zoom_out()
  local win = vim.api.nvim_get_current_win()
  if vim.w[win].zoom_origin then
    close_float(win)
    return true
  end
  if vim.t.zoom_origin then
    close_tab()
    return true
  end
  return false
end

function M.toggle_float()
  if not zoom_out() then open_float() end
end

function M.toggle_tab()
  if not zoom_out() then open_tab() end
end

return M
