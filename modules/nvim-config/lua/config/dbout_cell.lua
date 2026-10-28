-- <Leader><CR> in dadbod's results (after/ftplugin/dbout.lua): the whole value under the cursor
-- in a read-only popup, titled with its column. JSON gets the json filetype, indented; HTML the
-- html filetype, and opens in the browser too, as paperboy's gb does: a page of its own with
-- no scripts, frames or forms, served as a URL over SSH when paperboy is loaded. In the popup,
-- <Esc> clears the search highlight, or closes it back on the cell when there is none, and z
-- zooms it to a tab (where <Esc> does the same).
--
-- The value comes from config/dbout_compact.lua (SQL Server, line breaks and all), or, for
-- results it did not lay out, from dadbod-ui's cell (as shown).
local M = {}

-- Policy of the page HTML opens as (paperboy's message.BROWSER_CSP): a value from a database
-- runs no scripts. Images and styles still load
local BROWSER_CSP = "script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"

-- Tag names that make markup HTML rather than some XML
local HTML_TAGS = {}
for tag in ([[a abbr address article aside b blockquote body br button caption center code col
  colgroup dd details div dl dt em fieldset figure font footer form h1 h2 h3 h4 h5 h6 head header
  hr html i iframe img input label li link main meta nav ol option p pre s section select small
  span strike strong style sub summary sup table tbody td textarea tfoot th thead title tr u ul]]):gmatch('%S+') do
  HTML_TAGS[tag] = true
end

local function is_json(text)
  if not text:match('^[%[{]') then return false end
  return (pcall(vim.json.decode, text))
end

--- Markup that tree-sitter's html parser reads without errors, with an HTML element in it
local function is_html(text)
  if not (text:match('^<') and text:match('>$')) then return false end
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, 'html')
  if not ok then return false end
  local root = parser:parse()[1]:root()
  if root:has_error() then return false end
  local html = false
  local function walk(node)
    for child in node:iter_children() do
      local type = child:type()
      if type == 'erroneous_end_tag' then return false end
      if type == 'doctype' or (type == 'tag_name' and HTML_TAGS[vim.treesitter.get_node_text(child, text):lower()]) then
        html = true
      end
      if walk(child) == false then return false end
    end
  end
  return walk(root) ~= false and html
end

--- JSON indented by two spaces, in its own order (vim.json would sort the keys)
local function indent_json(text)
  local out, depth, i, n = {}, 0, 1, #text
  local function newline() table.insert(out, '\n' .. ('  '):rep(depth)) end
  while i <= n do
    local char = text:sub(i, i)
    if char == '"' then
      local j = i + 1
      while true do
        j = text:find('["\\]', j)
        if text:sub(j, j) == '"' then break end
        j = j + 2
      end
      table.insert(out, text:sub(i, j))
      i = j
    elseif char == '{' or char == '[' then
      local empty = text:match('^%s*[%]}]()', i + 1)
      if empty then
        table.insert(out, char .. (char == '{' and '}' or ']'))
        i = empty - 1
      else
        table.insert(out, char)
        depth = depth + 1
        newline()
      end
    elseif char == '}' or char == ']' then
      depth = depth - 1
      newline()
      table.insert(out, char)
    elseif char == ',' then
      table.insert(out, ',')
      newline()
    elseif char == ':' then
      table.insert(out, ': ')
    elseif not char:match('%s') then
      table.insert(out, char)
    end
    i = i + 1
  end
  return table.concat(out)
end

local function open_in_browser(html)
  local path = vim.fn.tempname() .. '.html'
  -- Ahead of the value, the <meta> tags land in the <head> the parser opens
  local head = ('<meta charset="utf-8">\n<meta http-equiv="Content-Security-Policy" content="%s">\n'):format(BROWSER_CSP)
  vim.fn.writefile(vim.split(head .. html, '\n', { plain = true }), path)
  local err
  local ok, attachments = pcall(require, 'paperboy.attachments')
  if ok then
    err = attachments.open_path(path)
  else
    _, err = vim.ui.open(path)
  end
  if err then vim.notify('dadbod: failed to open the browser: ' .. err, vim.log.levels.ERROR) end
end

--- The value under the cursor and its column, from dadbod-ui's cell when dbout_compact has none
local function cell()
  local dbout = require('config.dbout_compact')
  -- The cursor's display column from the text: virtcol() counts showbreak's cells on a wrap
  local vcol = vim.api.nvim_strwidth(vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1))
  local value, column = dbout.value_at(0, vim.fn.line('.'), vcol)
  if value then return value, column end

  local view = vim.fn.winsaveview()
  vim.fn['db_ui#dbout#get_cell_value']()
  if vim.fn.mode() ~= 'v' then return nil end
  local region = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = 'v' })
  vim.cmd('normal! \27')
  vim.fn.winrestview(view)
  return table.concat(region, '\n')
end

function M.open()
  local value, column = cell()
  if not value then return end
  local origin, cursor = vim.api.nvim_get_current_win(), vim.api.nvim_win_get_cursor(0)
  value = vim.trim((value:gsub('\r\n?', '\n')))
  local dbout = require('config.dbout_compact')
  if vim.fn.strchars(value) >= dbout.SQLCMD_MAX then
    vim.notify(('dadbod: the value may be cut at sqlcmd\'s %d characters'):format(dbout.SQLCMD_MAX),
      vim.log.levels.WARN)
  end

  local filetype = 'text'
  if is_json(value) then
    filetype, value = 'json', indent_json(value)
  elseif is_html(value) then
    filetype = 'html'
    open_in_browser(value)
  end

  local lines = vim.split(value, '\n', { plain = true })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = filetype
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  local widest = 1
  for _, line in ipairs(lines) do
    widest = math.max(widest, vim.api.nvim_strwidth(line))
  end
  local width = math.min(math.max(widest, 40), math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    border = 'rounded',
    title = column and (' %s '):format(column) or nil,
    title_pos = column and 'center' or nil,
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- Left any other way, it goes too: a float out of focus only covers the results
  local leave = vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end,
  })

  -- Closed with <Esc>, from the popup or its tab, back on the cell: on its own, NeoVim leaves
  -- a float for the first window, the query above dadbod's results
  vim.keymap.set('n', '<Plug>(DboutCellClose)', function()
    pcall(vim.api.nvim_del_autocmd, leave)
    vim.api.nvim_win_close(0, true)
    if vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
      pcall(vim.api.nvim_win_set_cursor, origin, cursor)
    end
  end, { buffer = buf })
  -- An expr: :nohlsearch in a function is undone when it returns
  vim.keymap.set('n', '<Esc>', function()
    return vim.v.hlsearch == 1 and '<cmd>nohlsearch<CR>' or '<Plug>(DboutCellClose)'
  end, { buffer = buf, expr = true, remap = true, desc = 'Clear the highlight, or close' })

  -- z in the popup zooms it to a tab of its own. The popup closes only once the tab shows the
  -- buffer, which goes with its last window. In the tab, z is NeoVim's again (zz, zt...)
  vim.keymap.set('n', '<Plug>(DboutCellZoom)', function()
    pcall(vim.api.nvim_del_autocmd, leave)
    vim.cmd.sbuffer({ buf, mods = { tab = vim.fn.tabpagenr() } })
    vim.wo.wrap, vim.wo.linebreak = true, true
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })
  vim.keymap.set('n', 'z', function()
    return vim.api.nvim_win_get_config(0).relative == '' and 'z' or '<Plug>(DboutCellZoom)'
  end, { buffer = buf, expr = true, remap = true, nowait = true, desc = 'Zoom to a tab' })
end

return M
