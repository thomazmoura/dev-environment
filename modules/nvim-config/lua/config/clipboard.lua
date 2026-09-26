-- Clipboard providers NeoVim can't detect on its own

if vim.env.WSLENV then
  vim.g.clipboard = {
    name = 'win32yank-wsl',
    copy = { ['+'] = 'win32yank.exe -i --crlf', ['*'] = 'win32yank.exe -i --crlf' },
    paste = { ['+'] = 'win32yank.exe -o --lf', ['*'] = 'win32yank.exe -o --lf' },
    cache_enabled = 0,
  }
elseif vim.env.SSH_CONNECTION and not vim.env.WAYLAND_DISPLAY then
  -- Over ssh (prefix+N) "+y goes to the clipboard of the machine you are
  -- ssh'ing from, as an OSC 52 escape the local tmux forwards to the terminal.
  -- SSH_CONNECTION rather than SSH_TTY because tmux's default
  -- update-environment carries it into a tmux started on the remote.
  --
  -- Paste gives back what this NeoVim last copied rather than asking the
  -- terminal for its clipboard, which blocks until it times out when nothing
  -- answers; paste from the local clipboard with the terminal's own paste.
  local osc52 = require('vim.ui.clipboard.osc52')
  local last = {}
  local function copy(register)
    local send = osc52.copy(register)
    return function(lines, regtype)
      last[register] = { lines, regtype }
      send(lines, regtype)
    end
  end
  local function paste(register)
    return function() return last[register] or { {}, 'v' } end
  end
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = { ['+'] = copy('+'), ['*'] = copy('*') },
    paste = { ['+'] = paste('+'), ['*'] = paste('*') },
  }
end
