-- "+ and "* as the clipboard of the device you're typing on: this machine's
-- display, the PC you ssh'd or linked from (prefix+N), or the phone. Asked on
-- every copy and paste (config/front_client.lua), since those take turns in
-- front of the same tmux while NeoVim runs.
--
--   local   Wayland's clipboard (wl-copy/wl-paste); with no display, OSC 52
--           and the last copy back.
--   remote  OSC 52 both ways, through tmux. Copy: tmux hands the escape to
--           every terminal showing the window (set-clipboard on,
--           modules/tmux/common.conf). Paste: `tmux refresh-client -l <pane>`
--           asks the front client's terminal for its clipboard and types the
--           answer into this pane, which NeoVim reads as a TermResponse.
--           A pane's own OSC 52 query (NeoVim's built-in paste) would get
--           tmux's paste buffer instead, never the terminal's clipboard.
--           Outside tmux (a plain ssh login) the query goes to the terminal.
--           Ghostty answers without asking (clipboard-read = allow,
--           modules/ghostty/config); a terminal that never answers costs a
--           second and pastes the last copy.
--   termux  The phone's clipboard sockets (config/termux_clipboard.lua), and
--           OSC 52 as well, which Termux takes but can't answer.
--
-- This machine's clipboard gets every copy too, when it has a display, so it
-- holds the same text once you're back at it.

if vim.env.WSLENV then
  vim.g.clipboard = {
    name = 'win32yank-wsl',
    copy = { ['+'] = 'win32yank.exe -i --crlf', ['*'] = 'win32yank.exe -i --crlf' },
    paste = { ['+'] = 'win32yank.exe -o --lf', ['*'] = 'win32yank.exe -o --lf' },
    cache_enabled = 0,
  }
  return
end

local osc52 = require('vim.ui.clipboard.osc52')
local front_client = require('config.front_client')
local termux = require('config.termux_clipboard')

-- How long the terminal in front gets to answer for its clipboard
local REMOTE_PASTE_TIMEOUT = 1000

--- What a provider gets and returns: lines plus a regtype, linewise when the
--- text ends in a newline. A linewise copy already comes with an empty last
--- line, so its text ends in one.
local function to_text(lines)
  return table.concat(lines, '\n')
end

local function to_register(text)
  local lines = vim.split((text:gsub('\r\n', '\n')), '\n', { plain = true })
  if #lines > 1 and lines[#lines] == '' then
    table.remove(lines)
    return { lines, 'V' }
  end
  return { lines, 'v' }
end

-- This machine's display, Wayland's as NeoVim would detect it by itself
local wayland = vim.env.WAYLAND_DISPLAY and vim.fn.executable('wl-copy') == 1 and vim.fn.executable('wl-paste') == 1

local function wl_args(command, register, ...)
  local list = { command, ... }
  if register == '*' then table.insert(list, 2, '--primary') end
  return list
end

local function wl_copy(register, lines)
  -- --foreground: it serves the copy until the next one takes over
  vim.system(wl_args('wl-copy', register, '--foreground', '--type', 'text/plain'),
    { stdin = to_text(lines), stdout = false, stderr = false, detach = true })
end

local function wl_paste(register)
  local result = vim.system(wl_args('wl-paste', register, '--no-newline'), { text = true }):wait(2000)
  if result.code ~= 0 then return nil end
  return to_register(result.stdout or '')
end

--- The terminal's clipboard over OSC 52 (see the header): in tmux the front
--- client's, through refresh-client; outside tmux (a plain ssh login) asked of
--- the terminal directly
---@param client string|nil tmux's name for the front client
---@return string|nil
local function remote_text(client)
  local text
  local id = vim.api.nvim_create_autocmd('TermResponse', {
    callback = function(args)
      local sequence = type(args.data) == 'table' and args.data.sequence or args.data
      local encoded = type(sequence) == 'string' and sequence:match('\027%]52;%w*;([A-Za-z0-9+/=]*)')
      if not encoded then return end
      local ok, decoded = pcall(vim.base64.decode, encoded)
      text = ok and decoded or ''
      return true
    end,
  })
  local asked
  if vim.env.TMUX then
    asked = client and vim.env.TMUX_PANE
      and vim.system({ 'tmux', 'refresh-client', '-l', vim.env.TMUX_PANE, '-t', client }):wait(1000).code == 0
  else
    asked = pcall(vim.api.nvim_ui_send, '\027]52;c;?\027\\')
  end
  if asked then
    vim.wait(REMOTE_PASTE_TIMEOUT, function() return text ~= nil end, 10)
  end
  pcall(vim.api.nvim_del_autocmd, id)
  return text
end

-- What this NeoVim last copied, per register: the paste of last resort
local last = {}

local function copy(register)
  return function(lines, regtype)
    last[register] = { lines, regtype }
    local front = front_client.get()
    if wayland then wl_copy(register, lines) end
    if front.kind == 'termux' then termux.copy(to_text(lines)) end
    -- Locally the display has it already; elsewhere (and with no display)
    -- it's the way to the terminal
    if front.kind ~= 'local' or not wayland then osc52.copy(register)(lines, regtype) end
  end
end

local function fallback(register, why)
  if why then vim.notify(why .. '; pasting what NeoVim last copied', vim.log.levels.WARN) end
  return last[register] or { {}, 'v' }
end

local function paste(register)
  return function()
    local front = front_client.get()
    if front.kind == 'termux' then
      local text = termux.paste()
      if text then return to_register(text) end
      return fallback(register, 'Could not read the Termux clipboard')
    elseif front.kind == 'remote' then
      local text = remote_text(front.name)
      if text then return to_register(text) end
      return fallback(register, "The terminal didn't answer for its clipboard")
    end
    if wayland then
      return wl_paste(register) or fallback(register)
    end
    return fallback(register)
  end
end

vim.g.clipboard = {
  name = 'device in front',
  copy = { ['+'] = copy('+'), ['*'] = copy('*') },
  paste = { ['+'] = paste('+'), ['*'] = paste('*') },
}
