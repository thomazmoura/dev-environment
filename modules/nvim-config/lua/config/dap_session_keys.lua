-- Alt mirrors of the <Leader>d{key} debug mappings (plugins/debug.lua), only
-- while a dap session is running: <M-j> steps over, <M-k> steps out, and so on.
-- gH and <CR> (inspect the value under the cursor) are taken the same way.
-- While a session runs, these replace whatever else holds those keys (Harpoon's
-- <M-j>/<M-k>/<M-l>/<M-o> slots). When the last session ends they're put back.
local M = {}

local mappings = {} -- { lhs, rhs, desc } from setup()
local saved = {} -- lhs -> the maparg() dict our mapping replaced, or false
local active = false

local function is_ours(lhs, rhs)
  local current = vim.fn.maparg(lhs, 'n', false, true)
  return current.callback == rhs and current.buffer == 0
end

-- Takes each key, saving the mapping it replaces. Also called when lazy.nvim
-- loads a plugin mid-session, since that resets the plugin's keys over ours
-- (the newly set mapping is then the one to put back).
local function enable()
  for _, map in ipairs(mappings) do
    local lhs, rhs, desc = map[1], map[2], map[3]
    if not is_ours(lhs, rhs) then
      local current = vim.fn.maparg(lhs, 'n', false, true)
      saved[lhs] = (current.lhs and current.buffer == 0) and current or false
      vim.keymap.set('n', lhs, rhs, { desc = desc })
    end
  end
  active = true
end

local function disable()
  for _, map in ipairs(mappings) do
    local lhs, rhs = map[1], map[2]
    if is_ours(lhs, rhs) then
      vim.keymap.del('n', lhs)
      if saved[lhs] then vim.fn.mapset('n', false, saved[lhs]) end
    end
  end
  saved = {}
  active = false
end

-- keys: { { '<M-j>', function, 'desc' }, ... }
function M.setup(keys)
  mappings = keys
  -- Called with the new current session whenever it changes; nil once the
  -- last one has ended (terminated, exited, detached or the adapter died)
  require('dap').listeners.on_session.dap_session_keys = function(_, new)
    if new and not active then
      enable()
    elseif not new and active then
      disable()
    end
  end
  vim.api.nvim_create_autocmd('User', {
    pattern = 'LazyLoad',
    group = vim.api.nvim_create_augroup('dap_session_keys', { clear = true }),
    callback = function()
      if active then vim.schedule(enable) end
    end,
  })
end

return M
