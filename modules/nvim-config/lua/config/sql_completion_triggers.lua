-- Where a space or a '(' opens blink's menu in a sql buffer (lua/plugins/completion.lua):
-- after a join's ON, for sqlserver-assist's join conditions, and after INSERT [INTO] <table> (,
-- for its column list (modules/sql-assist). Blink blocks both characters everywhere else, so
-- typing a space doesn't list the buffer's words. The server makes the same checks itself.
-- M.attach opens the menu after a '(' that nvim-autopairs paired (see there).
local M = {}

local group = vim.api.nvim_create_augroup('SqlCompletionTriggers', { clear = true })

--- The column the word being typed after an ON starts at (0-based), or nil when the text
--- before the cursor isn't `ON <word>`. ON may end a line above
function M.after_on(buf, row, col)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
    row, col = unpack(vim.api.nvim_win_get_cursor(0))
  end
  if vim.bo[buf].filetype ~= 'sql' then return nil end
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:sub(1, col)
  local word = line:match('[%w_]*$')
  local before = line:sub(1, #line - #word)
  while before:match('^%s*$') and row > 1 do
    row = row - 1
    before = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] .. ' '
  end
  if before:match('%f[%w_][Oo][Nn]%s+$') then return col - #word end
end

-- How many lines above the cursor the INSERT may start
local LINES = 20

--- Whether text is a table's name as written: parts like dbo, [My Table] or "x", joined by dots
local function is_name(text)
  local i = 1
  while true do
    local part = text:match('^%b[]', i) or text:match('^"[^"]*"', i) or text:match('^[%w_@#$]+', i)
    if not part then return false end
    i = i + #part
    if i > #text then return true end
    if text:sub(i, i) ~= '.' then return false end
    i = i + 1
  end
end

--- The table named by the INSERT whose column list is opened right before the cursor, as
--- written, and the column the word being typed after its '(' starts at (0-based), or nil
--- when the text before the cursor isn't `INSERT [INTO] <table> (<word>`. It may span lines
function M.after_insert(buf, row, col)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
    row, col = unpack(vim.api.nvim_win_get_cursor(0))
  end
  if vim.bo[buf].filetype ~= 'sql' then return nil end
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:sub(1, col)
  local word = line:match('%(%s*([%w_]*)$')
  if not word then return nil end
  local lines = vim.api.nvim_buf_get_lines(buf, math.max(0, row - 1 - LINES), row - 1, false)
  table.insert(lines, line)
  local text = table.concat(lines, '\n')

  -- After the last INSERT
  local last
  for at in text:gmatch('()%f[%w_][Ii][Nn][Ss][Ee][Rr][Tt]%f[^%w_]') do last = at end
  if not last then return nil end
  local rest = text:sub(last + #'INSERT'):gsub('^%s+[Ii][Nn][Tt][Oo]%f[^%w_]', '')
  local name = rest:match('^%s+(.-)%s*%(%s*[%w_]*$')
  if name and is_name(name) then return name, col - #word end
end

--- nvim-autopairs types an INSERT's '(' as '()' in one change, so blink takes ')' for the
--- character typed, which triggers nothing: with the cursor inside a pair just opened after
--- INSERT [INTO] <table>, the menu is shown here. Scheduled: blink's own TextChangedI, which
--- hides the menu on that ')', runs after this one
function M.attach(buf)
  vim.api.nvim_clear_autocmds({ group = group, buffer = buf })
  vim.api.nvim_create_autocmd('TextChangedI', {
    group = group,
    buffer = buf,
    callback = function()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      if vim.api.nvim_get_current_line():sub(col, col + 1) == '()' and M.after_insert(buf, row, col) then
        vim.schedule(function() require('blink.cmp').show({ providers = { 'sql_assist' } }) end)
      end
    end,
  })
end

return M
