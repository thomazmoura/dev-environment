-- The phone's clipboard, while the tmux client in front is Termux -- used by
-- config/clipboard.lua for "+ and "*.
--
-- Termux's ssh forwards two Unix sockets back to the phone (RemoteForward, set
-- up by Termux/termux-setup.sh), where socat hands each connection to
-- termux-clipboard-get or termux-clipboard-set (Termux:API):
--
--   /tmp/termux-clipboard-<user>-get.sock   connect, read the clipboard
--   /tmp/termux-clipboard-<user>-set.sock   write the text, close the write side
--
-- Both answer "ok\n" first when the Termux:API call worked (get then sends the
-- text). That tells a working phone from a forward whose listener is gone:
-- ssh still accepts the connection then and just closes it.
--
-- sshd creates the sockets 0600, so only this user can read the phone's
-- clipboard. The host's sshd needs StreamLocalBindUnlink, or the socket the
-- last connection left behind blocks the next forward
-- (LinuxDevEnv/sshd-setup.sh).

local M = {}

local user = vim.uv.os_get_passwd().username

local function socket(kind)
  return ('/tmp/termux-clipboard-%s-%s.sock'):format(user, kind)
end

--- Whether the terminal you're typing on is Termux. In tmux that's the
--- session's most recently active client, read on every call: the PC and the
--- phone take turns while NeoVim runs. Termux announces itself with
--- LC_TERMINAL=Termux in the tmux client's environment, as for
--- modules/tmux/scripts/Set-PaneBackground.sh.
function M.in_front()
  if not vim.env.TMUX then
    return vim.env.LC_TERMINAL == 'Termux'
  end
  local result = vim.system({ 'tmux', 'display-message', '-p', '#{client_pid}' }, { text = true }):wait()
  local pid = vim.trim(result.stdout or '')
  if not pid:match('^%d+$') then return false end
  local file = io.open('/proc/' .. pid .. '/environ', 'rb')
  if not file then return false end
  local environ = file:read('*a')
  file:close()
  return ('\0' .. environ):find('\0LC_TERMINAL=Termux\0', 1, true) ~= nil
end

--- Talks to one of the sockets: sends data (then EOF) if given, and returns
--- what came back before the other side closed, or nil on error or timeout.
local function exchange(kind, data, timeout)
  local path = socket(kind)
  if not vim.uv.fs_stat(path) then return nil end

  local pipe = vim.uv.new_pipe(false)
  local done, failed, chunks = false, false, {}
  local function finish(err)
    if done then return end
    done, failed = true, err ~= nil
    if not pipe:is_closing() then pipe:close() end
  end

  pipe:connect(path, function(err)
    if err then return finish(err) end
    pipe:read_start(function(read_err, chunk)
      if read_err then return finish(read_err) end
      if chunk then
        chunks[#chunks + 1] = chunk
      else
        finish()
      end
    end)
    -- get gets no EOF from here: socat would give termux-clipboard-get only
    -- half a second to answer after one
    if data then
      pipe:write(data, function(write_err)
        if write_err then return finish(write_err) end
        pipe:shutdown()
      end)
    end
  end)

  if not vim.wait(timeout, function() return done end, 10) then finish('timeout') end
  if failed then return nil end
  return table.concat(chunks)
end

--- Puts text on the phone's clipboard; false if it didn't get there
function M.copy(text)
  return exchange('set', text, 3000) == 'ok\n'
end

--- The phone's clipboard as text, or nil if it couldn't be read
function M.paste()
  local answer = exchange('get', nil, 3000)
  if not answer or answer:sub(1, 3) ~= 'ok\n' then return nil end
  return answer:sub(4)
end

return M
