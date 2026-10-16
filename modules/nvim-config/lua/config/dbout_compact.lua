-- Narrows the columns of SQL Server results (sqlcmd's output in dadbod's .dbout buffers) to
-- their widest value. sqlcmd pads every cell to the column's declared width, 256 characters
-- for varchar(max) and other max types (its -y default), however short the values are.
-- Called on BufReadPost *.dbout from lua/plugins/database.lua, so each query and each reload.
--
-- A result is a header line over a line of dashes, one run per column split by single
-- spaces (what dadbod-ui's cell yank and folds read too), then rows up to the blank line.
-- sqlcmd counts the padding in characters. Numbers stay right-aligned, as sqlcmd prints them.
-- Rows of another length (a value with a line break) are kept as they are.
local M = {}

--- The columns of a dashes line, as { from = first character (0-based), len = characters }
local function columns(dashes)
  local cols = {}
  for from, run in dashes:gmatch('()(%-+)') do
    table.insert(cols, { from = from - 1, len = #run })
  end
  return cols
end

local function is_dashes(line)
  return line:match('^%-+$') ~= nil or line:match('^%-[%- ]*%-$') ~= nil and not line:find('  ', 1, true)
end

local function is_ascii(line)
  return not line:find('[\128-\255]')
end

local function sub(line, ascii, from, len)
  if ascii then return line:sub(from + 1, from + len) end
  return vim.fn.strcharpart(line, from, len)
end

local function width(text)
  if is_ascii(text) then return #text end
  return vim.fn.strdisplaywidth(text)
end

--- The result starting at lines[first] (its header), compacted; and the line after it
local function compact_result(lines, first)
  local cols = columns(lines[first + 1])
  local length = #lines[first + 1]
  local last = first + 1
  while lines[last + 1] and lines[last + 1] ~= '' do
    last = last + 1
  end

  -- cells[i][c]: line first + i - 1, column c, trimmed (nil for a row of another length)
  local cells, widths, right = {}, {}, {}
  for c, col in ipairs(cols) do
    widths[c], right[c] = 0, nil
  end
  for i = first, last do
    local line = lines[i]
    local ascii = is_ascii(line)
    if i ~= first + 1 and (ascii and #line or vim.fn.strchars(line)) == length then
      local row = {}
      for c, col in ipairs(cols) do
        local cell = sub(line, ascii, col.from, col.len)
        row[c] = vim.trim(cell)
        widths[c] = math.max(widths[c], width(row[c]))
        -- Right-aligned: every value of the column ends on its last character
        if i > first + 1 and row[c] ~= '' then
          right[c] = right[c] ~= false and cell:sub(-1) ~= ' '
        end
      end
      cells[i - first + 1] = row
    end
  end

  local out = {}
  for i = first, last do
    local row = cells[i - first + 1]
    if i == first + 1 then
      local runs = {}
      for c in ipairs(cols) do
        runs[c] = ('-'):rep(math.max(widths[c], 1))
      end
      table.insert(out, table.concat(runs, ' '))
    elseif row then
      local parts = {}
      for c, cell in ipairs(row) do
        local pad = (' '):rep(math.max(widths[c], 1) - width(cell))
        parts[c] = (right[c] and i > first + 1) and pad .. cell or cell .. pad
      end
      table.insert(out, (table.concat(parts, ' '):gsub('%s+$', '')))
    else
      table.insert(out, lines[i])
    end
  end
  return out, last + 1
end

function M.compact(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out, i, changed = {}, 1, false
  while i <= #lines do
    if lines[i + 1] and lines[i] ~= '' and is_dashes(lines[i + 1]) then
      local result, after = compact_result(lines, i)
      vim.list_extend(out, result)
      i, changed = after, true
    else
      table.insert(out, lines[i])
      i = i + 1
    end
  end
  if not changed then return end

  -- As read from the file: not modified, and no undo step back to the padded text. dadbod's
  -- preview window is nomodifiable (and readonly), so that is lifted for the rewrite only
  local bo = vim.bo[buf]
  local undolevels, modifiable = bo.undolevels, bo.modifiable
  bo.undolevels, bo.modifiable = -1, true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  bo.undolevels, bo.modifiable, bo.modified = undolevels, modifiable, false
end

return M
