-- Clipboard providers NeoVim can't detect on its own, and the phone's clipboard
-- while tmux is driven from Termux

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

-- The provider this machine would use without the phone: copy(register,
-- lines, regtype) and paste(register) -> { lines, regtype }
local base
if vim.env.SSH_CONNECTION and not vim.env.WAYLAND_DISPLAY then
  -- Over ssh (prefix+N) "+y goes to the clipboard of the machine you are
  -- ssh'ing from, as an OSC 52 escape the local tmux forwards to the terminal.
  -- SSH_CONNECTION rather than SSH_TTY because tmux's default
  -- update-environment carries it into a tmux started on the remote.
  --
  -- Paste gives back what this NeoVim last copied rather than asking the
  -- terminal for its clipboard, which blocks until it times out when nothing
  -- answers; paste from the local clipboard with the terminal's own paste.
  local last = {}
  base = {
    name = 'OSC 52',
    osc52 = true,
    copy = function(register, lines, regtype)
      last[register] = { lines, regtype }
      osc52.copy(register)(lines, regtype)
    end,
    paste = function(register) return last[register] or { {}, 'v' } end,
  }
elseif vim.env.WAYLAND_DISPLAY and vim.fn.executable('wl-copy') == 1 then
  -- What NeoVim would detect by itself, spelled out because a provider of our
  -- own (for the phone, below) replaces the detection
  local function args(command, register, ...)
    local list = { command, ... }
    if register == '*' then table.insert(list, 2, '--primary') end
    return list
  end
  base = {
    name = 'wl-copy',
    copy = function(register, lines, regtype)
      -- --foreground: it serves the copy until the next one takes over
      vim.system(args('wl-copy', register, '--foreground', '--type', 'text/plain'),
        { stdin = to_text(lines), stdout = false, stderr = false, detach = true })
    end,
    paste = function(register)
      local result = vim.system(args('wl-paste', register, '--no-newline'), { text = true }):wait(2000)
      if result.code ~= 0 then return { {}, 'v' } end
      return to_register(result.stdout or '')
    end,
  }
else
  return
end

-- The phone (config/termux_clipboard.lua): with Termux the client in front,
-- copies also go to its clipboard and pastes come from it. Copies still go to
-- the base too, so the PC's clipboard holds the same text once you're back. A
-- copy the phone's socket didn't take goes out as OSC 52 instead, which tmux
-- forwards to Termux (set-clipboard on, modules/tmux/common.conf).
local termux = require('config.termux_clipboard')

local function copy(register)
  return function(lines, regtype)
    base.copy(register, lines, regtype)
    if termux.in_front() and not termux.copy(to_text(lines)) and not base.osc52 then
      osc52.copy(register)(lines, regtype)
    end
  end
end

local function paste(register)
  return function()
    if termux.in_front() then
      local text = termux.paste()
      if text then return to_register(text) end
      vim.notify('Could not read the Termux clipboard; pasting from ' .. base.name, vim.log.levels.WARN)
    end
    return base.paste(register)
  end
end

vim.g.clipboard = {
  name = base.name .. ' + Termux',
  copy = { ['+'] = copy('+'), ['*'] = copy('*') },
  paste = { ['+'] = paste('+'), ['*'] = paste('*') },
}
