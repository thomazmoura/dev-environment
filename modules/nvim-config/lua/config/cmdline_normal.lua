-- The command line (:, /, input() prompts) with a normal mode, like a Telescope
-- prompt: <Esc> turns noice's popup into the command-line window, floating in
-- the popup's place and in normal mode. Entering insert (i, a, A, cw...) goes
-- back to the command line with the cursor there, <CR> runs the line and a
-- second <Esc> cancels. Macros keep the plain <Esc>.
local map = vim.keymap.set

-- The look of noice's popup, taken on <Esc> for the CmdwinEnter that follows
local popup

-- noice's cmdline popup: a content window inside a nui border window
local function noice_popup()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local cfg = vim.api.nvim_win_get_config(win)
    if vim.bo[buf].filetype == 'noice' and cfg.relative == 'win'
        and vim.wo[win].winhighlight:match('NoiceCmdlinePopup') then
      local border = cfg.win
      local pos = vim.api.nvim_win_get_position(border)
      local title = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(border), 0, 1, false)[1] or ''
      -- Only the border's lines go: the spaces around the title are noice's
      title = title:gsub('^[╭─]+', ''):gsub('[─╮]+$', '')

      -- What comes before the text (noice's icon, virtual text over spaces),
      -- for the statuscolumn
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ''
      local cmd = vim.fn.getcmdline()
      local prefix = cmd == '' and line:gsub('%s$', '') or line:sub(1, (line:find(cmd, 1, true) or 1) - 1)
      local pieces = { { prefix } }
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
        local d = mark[4]
        if d.virt_text_pos == 'win_col' and d.virt_text_win_col < #prefix then
          local text = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, d.virt_text))
          local col = d.virt_text_win_col
          pieces = {
            { prefix:sub(1, col) },
            { text, d.virt_text[1][2] },
            { prefix:sub(col + vim.fn.strdisplaywidth(text) + 1) },
          }
          break
        end
      end
      local whl = vim.wo[win].winhighlight
      local statuscolumn = ''
      for _, piece in ipairs(pieces) do
        statuscolumn = statuscolumn .. (piece[2] and ('%#' .. piece[2] .. '#') or '%*') .. piece[1]:gsub('%%', '%%%%')
      end

      return {
        row = pos[1],
        col = pos[2],
        width = vim.api.nvim_win_get_width(border) - 2,
        title = vim.trim(title) ~= '' and title or nil,
        winhighlight = whl .. ',LineNr:' .. (whl:match('Normal:([^,]+)') or 'NormalFloat'),
        statuscolumn = statuscolumn .. '%*',
      }
    end
  end
end

map('c', '<Esc>', function()
  if vim.fn.reg_executing() ~= '' or vim.fn.getcmdwintype() ~= '' then return '<C-c>' end
  popup = noice_popup()
  return vim.o.cedit
end, { expr = true, desc = 'Command line in normal mode' })

vim.api.nvim_create_autocmd('CmdwinEnter', {
  group = vim.api.nvim_create_augroup('cmdline_normal', { clear = true }),
  callback = function(args)
    map('n', '<Esc>', '<cmd>quit<cr>', { buffer = args.buf, desc = 'Cancel command line' })

    -- Opened by q: (or without noice): the usual split with the history
    local p = popup
    popup = nil
    if not p then return end

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_config(win, {
      relative = 'editor', row = p.row, col = p.col, width = p.width, height = 1,
      border = 'rounded', title = p.title, title_pos = p.title and 'center' or nil, zindex = 200,
    })
    local wo = vim.wo[win]
    wo.winhighlight = p.winhighlight
    wo.number, wo.relativenumber, wo.cursorline, wo.wrap = false, false, false, false
    wo.signcolumn, wo.foldcolumn, wo.statuscolumn = 'no', '0', p.statuscolumn

    -- The window draws its type (':', '/') in the first column, noice's
    -- padding: a blank cell covers it
    local blank = vim.api.nvim_create_buf(false, true)
    vim.bo[blank].bufhidden = 'wipe'
    local cover = vim.api.nvim_open_win(blank, false, {
      relative = 'editor', row = p.row + 1, col = p.col + 1, width = 1, height = 1,
      style = 'minimal', focusable = false, zindex = 201,
    })
    vim.wo[cover].winhighlight = p.winhighlight
    vim.api.nvim_create_autocmd('BufWinLeave', {
      buffer = args.buf,
      once = true,
      callback = function() pcall(vim.api.nvim_win_close, cover, true) end,
    })

    -- Insert goes back to the command line, with the cursor where it was here
    vim.api.nvim_create_autocmd('InsertEnter', {
      buffer = args.buf,
      once = true,
      callback = vim.schedule_wrap(function()
        local after = vim.api.nvim_get_current_line():sub(vim.fn.col('.'))
        local keys = '<C-c><End>' .. string.rep('<Left>', vim.fn.strchars(after))
        vim.api.nvim_feedkeys(vim.keycode(keys), 'ni', false)
      end),
    })
  end,
})
