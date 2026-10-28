-- Lays out SQL Server results (sqlcmd's output in dadbod's .dbout buffers) as columns as wide
-- as their widest shown value, and keeps every value whole for yic (after/ftplugin/dbout.lua).
-- Called on BufReadPost *.dbout from lua/plugins/database.lua, so each query and each reload.
--
-- autoload/sqlserver_locksmith.vim runs queries with sqlcmd -W -y 8000 -s <unit separator>:
-- values unpadded, up to sqlcmd's 8000-character maximum (its default cuts max types at 256),
-- split by a character no value holds. A value with a line break spans lines, joined back
-- here by counting separators: a row holds one less than its columns. On screen only, line
-- breaks show as ↵ and values past MAX_WIDTH are cut with ….
--
-- A result is a header over a line of dashes (one run per column, what dadbod-ui's cell yank
-- and folds read too), then rows up to a blank line; messages and row counts are kept as they
-- are. Lines with no separator after a whole row are the rest of its last value, so only the
-- line breaks of a first column are misread (of a single column, always). A result whose rows
-- do not add up is kept as sqlcmd printed it, separators shown as spaces.
local M = {}

local SEP = '\31'

-- Widest a value is shown, in display cells
local MAX_WIDTH = 80

-- sqlcmd's maximum for -y: a value this long was most likely cut there
M.SQLCMD_MAX = 8000

-- buf → lnum → { cols = { { from, to }... } (0-based display columns), values = { whole... },
-- header = { column names... } }
local cells = {}

local function separators(line)
  local _, n = line:gsub(SEP, '')
  return n
end

local function split(line)
  return vim.split(line, SEP, { plain = true })
end

local function is_dashes(line)
  if not line or line == '' then return false end
  for _, run in ipairs(split(line)) do
    if not run:match('^%-+$') then return false end
  end
  return true
end

local function width(text)
  if not text:find('[\128-\255]') then return #text end
  return vim.api.nvim_strwidth(text)
end

--- value as shown: line breaks as ↵, tabs as spaces, at most MAX_WIDTH cells
local function shown(value)
  local text = value:gsub('\r?\n', '↵'):gsub('\r', '↵'):gsub('\t', ' ')
  if width(text) <= MAX_WIDTH then return text end
  local n = MAX_WIDTH - 1
  local cut = vim.fn.strcharpart(text, 0, n)
  while width(cut) > MAX_WIDTH - 1 do
    n = n - 1
    cut = vim.fn.strcharpart(text, 0, n)
  end
  return cut .. '…'
end

--- The rows of the result whose header is lines[first], as lists of values, and the line after
--- it; nil when they do not add up
local function parse(lines, first, ncols)
  local rows, i = {}, first + 2
  local pending, count -- the lines of a row read so far, and their separators
  while lines[i] do
    local line = lines[i]
    if pending then
      table.insert(pending, line)
      count = count + separators(line)
    elseif line == '' then
      break
    elseif #rows > 0 and ncols > 1 and not line:find(SEP, 1, true) then
      local row = rows[#rows]
      row[ncols] = row[ncols] .. '\n' .. line
    else
      pending, count = { line }, separators(line)
    end
    if pending and count >= ncols - 1 then
      if count > ncols - 1 then return nil end
      table.insert(rows, split(table.concat(pending, '\n')))
      pending = nil
    end
    i = i + 1
  end
  if pending then return nil end
  return rows, i
end

--- Appends the result to out, and the whole values of its lines to found
local function render(header, rows, out, found)
  local widths, right, texts = {}, {}, {}
  for c, name in ipairs(header) do
    widths[c] = math.max(width(name), 1)
  end
  for r, row in ipairs(rows) do
    texts[r] = {}
    for c, value in ipairs(row) do
      texts[r][c] = shown(value)
      widths[c] = math.max(widths[c], width(texts[r][c]))
      -- Right-aligned, as sqlcmd prints numbers: every value of the column is one
      if value ~= 'NULL' and value ~= '' then
        right[c] = right[c] ~= false and value:match('^%-?%d+%.?%d*$') ~= nil
      end
    end
  end

  local cols, from = {}, 0
  for c, w in ipairs(widths) do
    cols[c] = { from, from + w - 1 }
    from = from + w + 1
  end

  local function add(line_texts, values, align)
    local parts = {}
    for c, text in ipairs(line_texts) do
      local pad = (' '):rep(widths[c] - width(text))
      parts[c] = (align and right[c]) and pad .. text or text .. pad
    end
    table.insert(out, (table.concat(parts, ' '):gsub('%s+$', '')))
    if values then found[#out] = { cols = cols, values = values, header = header } end
  end

  add(header, header, false)
  local dashes = {}
  for c, w in ipairs(widths) do
    dashes[c] = ('-'):rep(w)
  end
  add(dashes, nil, false)
  for r, row in ipairs(rows) do
    add(texts[r], row, true)
  end
end

function M.compact(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out, found, i = {}, {}, 1
  while i <= #lines do
    local header, dashes = lines[i], lines[i + 1]
    local rows, after
    if header ~= '' and is_dashes(dashes) and separators(header) == separators(dashes) then
      rows, after = parse(lines, i, separators(dashes) + 1)
    end
    if rows then
      render(split(header), rows, out, found)
      i = after
    else
      table.insert(out, (lines[i]:gsub(SEP, ' ')))
      i = i + 1
    end
  end

  if not cells[buf] then
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = function() cells[buf] = nil end,
    })
  end
  cells[buf] = found
  if vim.deep_equal(out, lines) then return end

  -- As read from the file: not modified, and no undo step back to sqlcmd's text. dadbod's
  -- preview window is nomodifiable (and readonly), so that is lifted for the rewrite only
  local bo = vim.bo[buf]
  local undolevels, modifiable = bo.undolevels, bo.modifiable
  bo.undolevels, bo.modifiable = -1, true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  bo.undolevels, bo.modifiable, bo.modified = undolevels, modifiable, false
end

--- The whole value at line lnum, display column vcol (0-based), of buf, and its column's name;
--- nil off a result laid out
function M.value_at(buf, lnum, vcol)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local row = (cells[buf] or {})[lnum]
  if not row then return nil end
  local c = 1
  for n, col in ipairs(row.cols) do
    if col[1] <= vcol then c = n end
  end
  return row.values[c], row.header[c]
end

return M
