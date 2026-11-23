-- PDFs open as Markdown: reading a *.pdf (nvim x.pdf, :e, a picker) fills the
-- buffer with what modules/pdf's pdf2md prints, converted in the background.
-- :e converts again, :w notes.md saves the Markdown.
--
-- The buffer keeps the PDF's name, so it must never be written: it is 'nowrite'
-- (:w and :w! fail with E382) and not modifiable (which auto-save skips too).
-- Not 'nofile', which markview doesn't render.

local INSTALL = 'pwsh ~/.modules/pdf/Install-PdfTools.ps1'

-- The conversion running for each buffer: only the latest one fills it
local running = {}

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function stop(buf)
  local job = running[buf]
  running[buf] = nil
  if job then job:kill('sigterm') end
end

-- ~/.local/bin isn't in the PATH of a NeoVim started outside the pwsh profile
local function converter()
  for _, command in ipairs({ 'pdf2md', vim.fs.normalize('~/.local/bin/pdf2md') }) do
    if vim.fn.executable(command) == 1 then return command end
  end
end

local function open(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  -- fugitive://, scp:// and the like have readers of their own
  if name:match('^%a[%w+.-]*://') then return end

  stop(buf)
  local bo = vim.bo[buf]
  bo.buftype = 'nowrite'
  bo.swapfile = false
  bo.undofile = false
  bo.undolevels = -1
  bo.modeline = false -- the text is whatever the PDF's author wrote
  set_lines(buf, { 'Converting ' .. vim.fs.basename(name):gsub('\n', ' ') .. '…' })
  bo.filetype = 'markdown'
  vim.opt_local.spell = false -- on from after/ftplugin/markdown.lua

  local command = converter()
  if not command then
    set_lines(buf, { 'pdf2md is not installed. To install it:', '', '    ' .. INSTALL })
    return
  end

  local job
  job = vim.system({ command, '--', name }, { text = true }, vim.schedule_wrap(function(result)
    if running[buf] ~= job then return end
    running[buf] = nil
    if not vim.api.nvim_buf_is_loaded(buf) then return end

    local output = result.stdout
    if result.code ~= 0 or result.signal ~= 0 then
      output = result.stderr ~= '' and result.stderr or 'pdf2md failed'
    end
    set_lines(buf, vim.split((output:gsub('\n$', '')), '\n', { plain = true }))
  end))
  running[buf] = job
end

local group = vim.api.nvim_create_augroup('PdfAsMarkdown', { clear = true })

vim.api.nvim_create_autocmd('BufReadCmd', {
  group = group,
  pattern = '*.[pP][dD][fF]',
  nested = true, -- for the FileType event
  callback = function(event) open(event.buf) end,
})

vim.api.nvim_create_autocmd('BufWipeout', {
  group = group,
  callback = function(event) stop(event.buf) end,
})
