-- gb in an html buffer (after/ftplugin/html.lua), in dadbod's results on an HTML cell and in
-- its popup (config/dbout_cell.lua): the HTML in the browser, on the device typing over SSH
-- (xray.nvim's open, a URL serving the file), vim.ui.open where xray is not around.
--
-- A file on disk opens as itself, so its relative links, styles and images resolve. Anything
-- else (the cell popup, a scratch buffer, a value from a database) opens as a page of its own
-- under paperboy's no-scripts policy: no scripts, frames or forms.
local M = {}

-- Policy of the page a value opens as (paperboy's message.BROWSER_CSP). Images and styles
-- still load
local BROWSER_CSP = "script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"

local function open_path(path)
  local err
  local ok, xray = pcall(require, 'xray.open')
  if ok then
    err = xray.open(path)
  else
    _, err = vim.ui.open(path)
  end
  if err then vim.notify('html: failed to open the browser: ' .. err, vim.log.levels.ERROR) end
end

--- HTML text in the browser, as a page with no scripts
---@param html string
function M.open_text(html)
  local path = vim.fn.tempname() .. '.html'
  -- Ahead of the value, the <meta> tags land in the <head> the parser opens
  local head = ('<meta charset="utf-8">\n<meta http-equiv="Content-Security-Policy" content="%s">\n'):format(BROWSER_CSP)
  vim.fn.writefile(vim.split(head .. html, '\n', { plain = true }), path)
  open_path(path)
end

--- A buffer in the browser: its file as saved, or its text when it has none
---@param buf integer|nil The current buffer when nil or 0
function M.open_buffer(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype == '' and name ~= '' and vim.fn.filereadable(name) == 1 then
    if vim.bo[buf].modified then
      vim.notify('html: showing the file as saved, without the unsaved changes', vim.log.levels.WARN)
    end
    open_path(name)
  else
    M.open_text(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
  end
end

return M
