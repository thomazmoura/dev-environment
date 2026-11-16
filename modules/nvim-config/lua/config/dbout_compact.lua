-- Lays out query results in dadbod's .dbout buffers, SQL Server's (sqlcmd) and Postgres's
-- (psql), as columns as wide as their widest shown value, and keeps every value whole for yic
-- (after/ftplugin/dbout.lua). Called on BufReadPost *.dbout from lua/plugins/database.lua, so
-- each query and each reload. On screen only, line breaks show as ↵ and values past MAX_WIDTH
-- are cut with ….
--
-- autoload/sqlserver_locksmith.vim runs queries with sqlcmd -W -y 8000 -s <unit separator>:
-- values unpadded, up to sqlcmd's 8000-character maximum (its default cuts max types at 256),
-- split by a character no value holds. A result is a header over a line of dashes (one run
-- per column), then rows up to a blank line. A value with a line break spans lines, joined back
-- here by counting separators: a row holds one less than its columns. Lines with no separator
-- after a whole row are the rest of its last value, so only the line breaks of a first column
-- are misread (of a single column, always). A result whose rows do not add up is kept as
-- sqlcmd printed it, separators shown as spaces.
--
-- autoload/postgresql_locksmith.vim runs queries with psql -A -F <unit separator> -P
-- recordsep=<record separator>: a result is its header, rows and (N rows) footer, split by the
-- record separator and ending at the line that ends with its footer, so line breaks are never
-- misread. Values are whole (psql cuts none), NULL shown as NULL. The footer is kept under the
-- result after a blank line, where sqlcmd prints its (N rows affected). A result whose rows do
-- not add up is kept as psql printed it, separators shown as spaces. Messages (UPDATE 3...) are
-- kept as they are, as sqlcmd's. In expanded display (\x, dadbod-ui's layout toggle), each
-- record is a table of its own, a row per column: it has no footer, so it ends at the first
-- line without a record separator, and a line break in its last value ends it there.
--
-- Both are laid out the same way: a header over a line of dashes (one run per column, what
-- dadbod-ui's cell yank and folds read too), then the rows. The space between columns shows
-- a │, and the dash line ─ and ┼: extmarks over the text, which stays as it is for dadbod-ui
-- and yic. Only the last column's padding is trimmed, so the empty cells at the end of a row
-- keep their │. The table's frame is extmarks too: a │ before each line and after its last
-- column (├ and ┤ on the dash line), inline so the text keeps its columns, and a ┌─┬─┐ line
-- above the header and └─┴─┘ below the last row. A result at the top of the file gets a blank
-- line above it to hold its ┌─┬─┐: NeoVim shows no virtual line above the first one (gg
-- scrolls past it).
local M = {}

local SEP = '\31'
-- psql's record separator
local RSEP = '\30'

-- Widest a value is shown, in display cells
local MAX_WIDTH = 80

-- sqlcmd's maximum for -y: a value this long was most likely cut there
M.SQLCMD_MAX = 8000

local ns = vim.api.nvim_create_namespace('dbout_compact')
vim.api.nvim_set_hl(0, 'DboutSeparator', { default = true, link = 'WinSeparator' })

-- buf → lnum → { cols = { { from, to }... } (0-based display columns), values = { whole... },
-- header = { column names... }, max = the length a value may have been cut at, or nil }
local cells = {}
-- buf → { { header = lnum, last = lnum }... }: where each result laid out starts and ends
local results = {}

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

--- The header, rows and footer of the psql result starting at lines[first], and the line after
--- it; nil when it is not one or its rows do not add up
local function parse_psql(lines, first)
  if not lines[first]:find(RSEP, 1, true) then return nil end
  local last = first
  while not lines[last]:match(RSEP .. '%(%d+ rows?%)$') do
    last = last + 1
    if not lines[last] then return nil end
  end
  local records = vim.split(table.concat(lines, '\n', first, last), RSEP, { plain = true })
  local footer = table.remove(records)
  local header = split(table.remove(records, 1))
  if #records ~= tonumber(footer:match('%d+')) then return nil end
  local rows = {}
  for r, record in ipairs(records) do
    rows[r] = split(record)
    if #rows[r] ~= #header then return nil end
  end
  return header, rows, footer, last + 1
end

--- The records of the psql result in expanded display (\x) starting at lines[first], each as
--- rows of { column, value }, and the line after it; nil when it is not one. It has no footer:
--- it ends at the first line holding no record separator, so a line break in its last value
--- ends it there
local function parse_psql_expanded(lines, first)
  if not lines[first]:find(SEP, 1, true) then return nil end
  local last = first
  while lines[last + 1] and lines[last + 1]:find(RSEP, 1, true) do last = last + 1 end
  local records, rows = {}, {}
  for _, field in ipairs(vim.split(table.concat(lines, '\n', first, last), RSEP, { plain = true })) do
    if field == '' then
      if #rows > 0 then table.insert(records, rows) end
      rows = {}
    else
      local name, value = field:match('^(.-)' .. SEP .. '(.*)$')
      if not name then return nil end
      table.insert(rows, { name, value })
    end
  end
  if #rows > 0 then table.insert(records, rows) end
  return records, last + 1
end

--- Appends the result to out, the whole values of its lines to found, and the separators to
--- draw over it to marks ({ line, byte, text }, 0-based) and its frame to frames
--- ({ line, side = 'left'|'right'|'above'|'below', text })
local function render(header, rows, out, found, marks, frames, max)
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
  local total = from - 1

  --- The line's │ (or the given characters) before it and after its last column
  local function frame(left, right)
    table.insert(frames, { #out - 1, 'left', left or '│' })
    table.insert(frames, { #out - 1, 'right', (' '):rep(total - width(out[#out])) .. (right or '│') })
  end
  --- A rule across the result: ─ over each column, the given corners and joints
  local function rule(left, joint, right)
    local runs = {}
    for c, w in ipairs(widths) do
      runs[c] = ('─'):rep(w)
    end
    return left .. table.concat(runs, joint) .. right
  end

  local function add(line_texts, values, align)
    local parts = {}
    for c, text in ipairs(line_texts) do
      local pad = (' '):rep(widths[c] - width(text))
      parts[c] = (align and right[c]) and pad .. text or text .. pad
    end
    parts[#parts] = parts[#parts]:gsub('%s+$', '')
    table.insert(out, table.concat(parts, ' '))
    if values then found[#out] = { cols = cols, values = values, header = header, max = max } end
    frame()
    local at = 0
    for c = 1, #parts - 1 do
      at = at + #parts[c]
      table.insert(marks, { #out - 1, at, '│' })
      at = at + 1
    end
  end

  add(header, header, false)
  table.insert(frames, { #out - 1, 'above', rule('┌', '┬', '┐') })
  local dashes = {}
  for c, w in ipairs(widths) do
    dashes[c] = ('-'):rep(w)
  end
  table.insert(out, table.concat(dashes, ' '))
  frame('├', '┤')
  -- One mark per character: an overlay hides whole once its start scrolls off to the left,
  -- so a single one across the line would vanish on the first zl
  for at = 0, #out[#out] - 1 do
    table.insert(marks, { #out - 1, at, out[#out]:sub(at + 1, at + 1) == '-' and '─' or '┼' })
  end
  for r, row in ipairs(rows) do
    add(texts[r], row, true)
  end
  table.insert(frames, { #out - 1, 'below', rule('└', '┴', '┘') })
end

function M.compact(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out, found, marks, frames, ranges, i = {}, {}, {}, {}, {}, 1
  -- Whether psql's expanded display (\x) is on, from its messages
  local expanded = false
  local function add(header, rows, max)
    if #out == 0 then table.insert(out, '') end
    local first = #out + 1
    render(header, rows, out, found, marks, frames, max)
    table.insert(ranges, { header = first, last = #out })
  end
  while i <= #lines do
    local header, dashes = lines[i], lines[i + 1]
    local rows, footer, after, records
    if header ~= '' and is_dashes(dashes) and separators(header) == separators(dashes) then
      rows, after = parse(lines, i, separators(dashes) + 1)
      if rows then add(split(header), rows, M.SQLCMD_MAX) end
    elseif expanded then
      -- Each record a table of its own, a row per column
      records, after = parse_psql_expanded(lines, i)
      for n, record in ipairs(records or {}) do
        add({ 'Column', 'Record ' .. n }, record)
      end
      rows = records
    else
      header, rows, footer, after = parse_psql(lines, i)
      if rows then
        add(header, rows)
        vim.list_extend(out, { '', footer })
      end
    end
    if rows then
      i = after
    else
      if lines[i]:match('^Expanded display is ') then expanded = lines[i]:match(' on%.$') ~= nil end
      table.insert(out, (lines[i]:gsub('[' .. SEP .. RSEP .. ']', ' ')))
      i = i + 1
    end
  end

  if not cells[buf] then
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = function() cells[buf], results[buf] = nil, nil end,
    })
  end
  cells[buf], results[buf] = found, ranges
  if not vim.deep_equal(out, lines) then
    -- As read from the file: not modified, and no undo step back to sqlcmd's text. dadbod's
    -- preview window is nomodifiable (and readonly), so that is lifted for the rewrite only
    local bo = vim.bo[buf]
    local undolevels, modifiable = bo.undolevels, bo.modifiable
    bo.undolevels, bo.modifiable = -1, true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
    bo.undolevels, bo.modifiable, bo.modified = undolevels, modifiable, false
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  -- The frame first: the ├ comes ahead of the ─ over the dash line's first character only when
  -- set ahead of it, or that ─ is drawn over the ├
  for _, mark in ipairs(frames) do
    local line, side, text = unpack(mark)
    if side == 'left' or side == 'right' then
      vim.api.nvim_buf_set_extmark(buf, ns, line, side == 'left' and 0 or #out[line + 1], {
        virt_text = { { text, 'DboutSeparator' } },
        virt_text_pos = 'inline',
      })
    else
      vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
        virt_lines = { { { text, 'DboutSeparator' } } },
        virt_lines_above = side == 'above',
        -- Scrolled sideways with the rows (zl), not cut at the window's edge
        virt_lines_overflow = 'scroll',
      })
    end
  end
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, mark[1], mark[2], {
      virt_text = { { mark[3], 'DboutSeparator' } },
      virt_text_pos = 'overlay',
      -- Scrolled off to the left, an overlay is otherwise drawn at the window's edge
      virt_text_hide = true,
    })
  end
end

--- The whole value at line lnum, display column vcol (0-based), of buf, its column's name, and
--- the length it may have been cut at (sqlcmd's maximum; nil for psql, which cuts none); nil
--- off a result laid out
function M.value_at(buf, lnum, vcol)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local row = (cells[buf] or {})[lnum]
  if not row then return nil end
  local c = 1
  for n, col in ipairs(row.cols) do
    if col[1] <= vcol then c = n end
  end
  return row.values[c], row.header[c], row.max
end

--- The header's line and the last row's of the result laid out that holds line lnum of buf;
--- nil off one
function M.result_at(buf, lnum)
  for _, range in ipairs(results[buf] or {}) do
    if range.header <= lnum and lnum <= range.last then return range.header, range.last end
  end
end

return M
