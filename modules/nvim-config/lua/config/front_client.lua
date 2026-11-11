-- The terminal you're typing on, for the clipboard: config/clipboard.lua (whose
-- clipboard "+ reads and writes) and config/paste_image.lua (whether this
-- machine's clipboard is yours).
--
-- In tmux that's the session's most recently active client, read on every
-- call: the PC, the phone and this machine's own desktop take turns while
-- NeoVim runs. The client process's environment says where it came from:
--
--   termux  LC_TERMINAL=Termux -- the phone, which announces itself
--           (Termux/termux-setup.sh), as for modules/tmux/scripts/Set-PaneBackground.sh
--   remote  SSH_CONNECTION -- another machine's terminal over ssh: a linked
--           machine's Connect-Tmux.sh loop, or a plain ssh + tmux attach
--   local   neither -- a terminal on this machine's own display
--
-- The pane's environment can't tell: a linked machine's tmux server was
-- started on its own desktop, so its panes have WAYLAND_DISPLAY whoever is
-- typing, and tmux's update-environment copies SSH_CONNECTION into them.
local M = {}

---@class FrontClient
---@field kind 'termux'|'remote'|'local'
---@field name string|nil tmux's client name (its tty), for refresh-client -t

--- Who is typing right now
---@return FrontClient
function M.get()
  if not vim.env.TMUX then
    -- SSH_TTY, not SSH_CONNECTION: only sshd sets it, in the login it serves
    if vim.env.LC_TERMINAL == 'Termux' then return { kind = 'termux' } end
    return { kind = vim.env.SSH_TTY and 'remote' or 'local' }
  end
  local ok, result = pcall(function()
    return vim.system({ 'tmux', 'display-message', '-p', '#{client_pid} #{client_name}' }, { text = true })
      :wait(1000)
  end)
  local pid, name = (ok and result.stdout or ''):match('^(%d+) (%S+)')
  if not pid then return { kind = 'local' } end
  local file = io.open('/proc/' .. pid .. '/environ', 'rb')
  if not file then return { kind = 'local', name = name } end
  local environ = '\0' .. file:read('*a')
  file:close()
  if environ:find('\0LC_TERMINAL=Termux\0', 1, true) then
    return { kind = 'termux', name = name }
  end
  if environ:find('\0SSH_CONNECTION=', 1, true) then
    return { kind = 'remote', name = name }
  end
  return { kind = 'local', name = name }
end

return M
