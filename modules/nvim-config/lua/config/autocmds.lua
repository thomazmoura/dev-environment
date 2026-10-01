local M = {}
local autocmd = vim.api.nvim_create_autocmd
local function group(name) return vim.api.nvim_create_augroup(name, { clear = true }) end

-- Flash what was yanked
autocmd('TextYankPost', {
  group = group('YankHighlight'),
  callback = function() vim.hl.on_yank({ higroup = 'TabLineSel', timeout = 450 }) end,
})

-- Back in a terminal buffer left with Ctrl+hjkl (plugins/tmux.lua), resume
-- terminal mode. Terminals left on purpose with <C-\><C-n> stay in normal mode.
autocmd('BufEnter', {
  group = group('TerminalRestore'),
  callback = function()
    if vim.bo.buftype == 'terminal' and vim.b.restore_terminal_mode then
      vim.b.restore_terminal_mode = false
      vim.cmd.startinsert()
    end
  end,
})

-- Select again what visual mode had when Ctrl+hjkl left it (plugins/tmux.lua),
-- from the same anchor to the same cursor, so o and the next motion still
-- work from the right end. Not if the window shows another buffer by now.
function M.restore_selection(selection)
  if vim.api.nvim_get_current_buf() ~= selection.buffer then return end
  vim.fn.setpos('.', selection.anchor)
  vim.cmd('normal! ' .. selection.mode)
  vim.fn.setpos('.', selection.cursor)
end

autocmd('WinEnter', {
  group = group('SelectionRestore'),
  callback = function()
    local selection = vim.w.restore_selection
    if selection then
      vim.w.restore_selection = nil
      M.restore_selection(selection)
    end
  end,
})

-- Conceal per buffer.
--
-- 'conceallevel' and 'concealcursor' are window-local, so when markview sets
-- them for a markdown buffer they stay on the window and conceal whatever comes
-- next (most visibly the quotes in JSON). Keep the intent per buffer instead
-- (vim.b.conceal_enabled, toggled by <Leader>mm) and re-apply it whenever a
-- buffer lands in a window.
M.markview_filetypes = { markdown = true, quarto = true, rmd = true, typst = true }

-- Filetypes that conceal on purpose (markview's or their own ftplugin's)
local concealing_filetypes = vim.tbl_extend('force', M.markview_filetypes, {
  help = true, man = true, rust = true, tex = true, latex = true, norg = true, org = true,
})

function M.apply_conceal()
  if concealing_filetypes[vim.bo.filetype] then return end
  local window = vim.wo[vim.api.nvim_get_current_win()]
  window.conceallevel = vim.b.conceal_enabled and 3 or 0
  window.concealcursor = vim.b.conceal_enabled and 'nc' or ''
end

autocmd({ 'BufWinEnter', 'BufEnter', 'WinEnter' }, {
  group = group('ConcealControl'),
  callback = M.apply_conceal,
})

return M
