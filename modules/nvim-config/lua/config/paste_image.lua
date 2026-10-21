-- Images in the clipboard pasted into Markdown, as Claude Code does: <Leader>p
-- and <Leader>P in a markdown buffer save a clipboard image to a file and
-- insert a Markdown image linking to it. Any other clipboard pastes as the
-- global <Leader>p does ("+p, keymaps/common.lua).
--
-- The terminal's own paste can't do this: with only an image in the clipboard
-- it has no text to send, so NeoVim never sees a paste. Reading the clipboard
-- here needs its owner's display: Wayland (wl-paste), X11 (xclip) or Windows
-- under WSL. Over ssh or in a container there is none, and it pastes text.
--
-- An image is saved beside the file, in images/, linked relatively. A buffer
-- with no file (paperboy's compose buffers) saves it in
-- stdpath('data')/pasted-images instead of /tmp, since a draft can be sent
-- after a reboot. Paperboy embeds PNG and JPEG images when sending.
local M = {}

-- Clipboard types tried in order: the formats paperboy can send come first
local PREFERRED = { 'image/png', 'image/jpeg' }

-- Keeps a clipboard owner that stopped answering from freezing NeoVim
local TIMEOUT_MS = 1000

local function run(cmd)
  local ok, result = pcall(function()
    return vim.system(cmd):wait(TIMEOUT_MS)
  end)
  if ok and result.code == 0 then
    return result.stdout
  end
end

--- The image type to read from the offered ones, if it holds one. Not when it
--- also offers plain text: spreadsheet cells and office text come with a
--- picture of themselves, and should paste as text
local function image_type(types)
  local offered = {}
  for _, type in ipairs(vim.split(types or '', '\n', { trimempty = true })) do
    offered[vim.trim(type)] = true
  end
  if offered['text/plain'] or offered['UTF8_STRING'] then
    return nil
  end
  for _, type in ipairs(PREFERRED) do
    if offered[type] then
      return type
    end
  end
  for type in pairs(offered) do
    if type:match('^image/') then
      return type
    end
  end
end

local function from_windows()
  -- One call checking and saving, as each powershell.exe start costs ~0.3s
  local temp = vim.fn.tempname() .. '.png'
  local windows_path = vim.trim(run({ 'wslpath', '-w', temp }) or '')
  if windows_path == '' then
    return nil
  end
  local script = ([[
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if ([Windows.Forms.Clipboard]::ContainsImage() -and -not [Windows.Forms.Clipboard]::ContainsText()) {
  [Windows.Forms.Clipboard]::GetImage().Save('%s', [Drawing.Imaging.ImageFormat]::Png)
}]]):format(windows_path:gsub("'", "''"))
  run({ 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script })
  local file = io.open(temp, 'rb')
  if not file then
    return nil
  end
  local data = file:read('*a')
  file:close()
  os.remove(temp)
  return { ext = 'png', data = data }
end

--- The clipboard's image, if it holds one
---@return table|nil { ext, data }
local function clipboard_image()
  local list, read
  if vim.env.WAYLAND_DISPLAY and vim.fn.executable('wl-paste') == 1 then
    list = { 'wl-paste', '--list-types' }
    read = function(type) return { 'wl-paste', '--no-newline', '--type', type } end
  elseif vim.env.DISPLAY and vim.fn.executable('xclip') == 1 then
    list = { 'xclip', '-selection', 'clipboard', '-t', 'TARGETS', '-o' }
    read = function(type) return { 'xclip', '-selection', 'clipboard', '-t', type, '-o' } end
  elseif vim.env.WSLENV and vim.fn.executable('powershell.exe') == 1 then
    return from_windows()
  else
    return nil
  end

  local type = image_type(run(list))
  local data = type and run(read(type))
  if not data or data == '' then
    return nil
  end
  local ext = type:match('^image/([%w]+)'):gsub('^jpeg$', 'jpg')
  return { ext = ext, data = data }
end

--- Where the buffer's images go, and how its links reach them
---@return string dir, string link_prefix
local function destination(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if vim.bo[bufnr].buftype == '' and name ~= '' then
    return vim.fs.dirname(name) .. '/images', 'images/'
  end
  local dir = vim.fn.stdpath('data') .. '/pasted-images'
  return dir, vim.fn.fnamemodify(dir, ':~') .. '/'
end

--- Paste from the clipboard: a Markdown image when it holds one, else "+p
---@param key string 'p' (after the cursor) or 'P' (before)
function M.paste(key)
  local image = clipboard_image()
  if not image then
    -- Its errors (an empty clipboard) shown as "+p shows them, without a traceback
    local ok, err = pcall(vim.cmd, ('normal! "+%d%s'):format(vim.v.count1, key))
    if not ok then
      vim.notify(tostring(err):match('E%d+:.*') or err, vim.log.levels.ERROR)
    end
    return
  end

  local dir, link_prefix = destination(0)
  vim.fn.mkdir(dir, 'p')
  -- Pasted twice in a second: the second gets a suffix
  local stamp = 'pasted-' .. os.date('%Y%m%d-%H%M%S')
  local base, n = stamp, 1
  while vim.uv.fs_stat(('%s/%s.%s'):format(dir, base, image.ext)) do
    n = n + 1
    base = ('%s-%d'):format(stamp, n)
  end
  local filename = base .. '.' .. image.ext
  local path = dir .. '/' .. filename

  local file, err = io.open(path, 'wb')
  if not file then
    vim.notify('Pasting the image failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  file:write(image.data)
  file:close()

  local link = link_prefix .. filename
  -- Angle brackets keep a path with spaces in one link
  if link:find(' ') then
    link = '<' .. link .. '>'
  end
  vim.api.nvim_put({ ('![%s](%s)'):format(base, link) }, 'c', key == 'p', true)
  vim.notify('Image saved to ' .. vim.fn.fnamemodify(path, ':~'))
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('paste_image', { clear = true }),
  pattern = 'markdown',
  callback = function(args)
    -- Buffer-local, over the global <Leader>p; visual mode keeps "+p
    for _, key in ipairs({ 'p', 'P' }) do
      vim.keymap.set('n', '<Leader>' .. key, function() M.paste(key) end, {
        buffer = args.buf,
        desc = key == 'p' and 'Paste from clipboard (images as links)'
          or 'Paste from clipboard before (images as links)',
      })
    end
  end,
})

return M
