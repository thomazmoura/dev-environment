-- Ghostty's crosshair on the cursor when moving between splits -- the NeoVim
-- half of modules/tmux/scripts/Show-PaneCrosshair.sh, which tmux's hooks run
-- when moving between panes. With both, C-h/j/k/l flashes the crosshair
-- wherever it lands.
--
-- Floating windows (Telescope, completion, hover) are skipped: entering one
-- isn't a split switch. Only inside tmux, which tells the script which client's
-- tty to flag; a NeoVim reached over ssh has neither the script nor the tty,
-- so its splits don't flash.

if not os.getenv('TMUX') then return end

local script = vim.fn.expand('~/.modules/tmux/scripts/Show-PaneCrosshair.sh')
if vim.fn.executable(script) == 0 then return end

local augroup = vim.api.nvim_create_augroup('PaneCrosshair', { clear = true })

-- The windows opened while starting up aren't a switch
local started = false
vim.api.nvim_create_autocmd('VimEnter', {
  group = augroup,
  callback = function() started = true end,
})

vim.api.nvim_create_autocmd('WinEnter', {
  group = augroup,
  callback = function()
    if not started or vim.api.nvim_win_get_config(0).relative ~= '' then return end
    vim.system({ script }, { detach = true })
  end,
})
