-- H and L in dadbod's results (after/ftplugin/dbout.lua) move to the previous and next cell of
-- the row, onto its value's first character (a count moves that many cells).
--
-- The cells are the runs of the dash line under the result's header, as dadbod-ui's ic reads
-- them: sqlcmd's (laid out by config/dbout_compact.lua, runs split by spaces) and psql's (by
-- +). They are display columns, matched to the row's text by width, so a ↵, an … or a wide
-- character before the cursor doesn't shift them. Off a result, H and L are NeoVim's.
local M = {}

local function is_dashes(line)
  return line ~= nil and line:match('^[+|]?%-[%- +|]*$') ~= nil
end

--- The dash line of the result the line lnum is in: the line itself, the one under a header,
--- or the nearest above, up to a blank line
local function dash_line(buf, lnum)
  local function get(n) return vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] end
  if is_dashes(get(lnum + 1)) then return get(lnum + 1) end
  for n = lnum, 1, -1 do
    local line = get(n)
    if line == '' then return nil end
    if is_dashes(line) then return line end
  end
end

--- The byte (0-based) of the character at display column vcol (0-based) of line, nil past its end
local function byte_at(line, vcol)
  local width, i = 0, 0
  while i < #line do
    local len = vim.str_utf_end(line, i + 1) + 1
    width = width + vim.api.nvim_strwidth(line:sub(i + 1, i + len))
    if width > vcol then return i end
    i = i + len
  end
end

--- Moves the cursor count cells left (-1) or right (1); false off a result
function M.move(direction, count)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local dashes = dash_line(0, row)
  if not dashes then return false end
  local cells = {}
  for from, to in dashes:gmatch('()%-+()') do
    table.insert(cells, { from - 1, to - 2 })
  end

  local line = vim.api.nvim_get_current_line()
  local vcol = vim.api.nvim_strwidth(line:sub(1, col))
  local current = 0
  for n, cell in ipairs(cells) do
    if cell[1] <= vcol then current = n end
  end
  local target = cells[math.max(1, math.min(#cells, current + direction * count))]
  if not target then return true end

  -- Onto the value's first character, as numbers are right-aligned; the line's end when the
  -- row stops before the cell (empty values at the end are trimmed)
  local first = byte_at(line, target[1])
  if not first then
    vim.api.nvim_win_set_cursor(0, { row, math.max(0, #line - 1) })
    return true
  end
  local last = byte_at(line, target[2] + 1) or #line
  local blank = line:sub(first + 1, last):find('%S')
  vim.api.nvim_win_set_cursor(0, { row, first + (blank or 1) - 1 })
  return true
end

return M
