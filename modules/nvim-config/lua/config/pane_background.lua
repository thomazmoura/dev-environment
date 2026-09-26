-- Opaque backgrounds when tmux was last attached from Termux, transparent
-- otherwise -- the NeoVim half of modules/tmux/scripts/Set-PaneBackground.sh.
--
-- Transparent, the terminal's background shows through and SpotlightDimmer
-- dims the unfocused splits. Termux has neither, so there the focused split
-- gets the lighter background and the rest the darker one, matching the tmux
-- panes. NeoVim then paints its own background, which tmux can't dim, so the
-- whole NeoVim goes dark while its tmux pane is unfocused.
--
-- The mode is tmux's @pane_background, read again on every FocusGained: the
-- client switching from the PC to the phone (or back) happens while NeoVim is
-- running. Outside tmux, Termux's own LC_TERMINAL=Termux over ssh decides.

local active = '#24283b'
local inactive = '#1a1b26'
local groups = { 'Normal', 'NormalNC', 'NvimTreeNormal', 'NvimTreeNormalNC' }

local opaque = false
local focused = true

local function read_mode()
  if os.getenv('TMUX') then
    local result = vim.system({ 'tmux', 'show-options', '-gqv', '@pane_background' }, { text = true }):wait()
    return vim.trim(result.stdout or '') == 'opaque'
  end
  return os.getenv('LC_TERMINAL') == 'Termux'
end

local function apply()
  for _, group in ipairs(groups) do
    local bg = 'none'
    if opaque then
      bg = (focused and not group:match('NC$')) and active or inactive
    end
    vim.cmd('highlight ' .. group .. ' guibg=' .. bg)
  end
end

local augroup = vim.api.nvim_create_augroup('PaneBackground', { clear = true })

-- After the colorscheme (plugins/colorscheme.lua), which sets these groups to none
vim.api.nvim_create_autocmd('VimEnter', {
  group = augroup,
  callback = function()
    opaque = read_mode()
    if opaque then apply() end
  end,
})

vim.api.nvim_create_autocmd('ColorScheme', {
  group = augroup,
  callback = function()
    if opaque then apply() end
  end,
})

vim.api.nvim_create_autocmd('FocusGained', {
  group = augroup,
  callback = function()
    local was_opaque = opaque
    opaque = read_mode()
    focused = true
    if opaque or was_opaque then apply() end
  end,
})

vim.api.nvim_create_autocmd('FocusLost', {
  group = augroup,
  callback = function()
    focused = false
    if opaque then apply() end
  end,
})
