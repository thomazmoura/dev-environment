-- Tmux navigation from an nvim on the other end of an ssh. The tmux there is
-- not ours: $TMUX is unset, so vim-tmux-navigator only moves between windows,
-- and the local tmux sees nothing but ssh on the pane's tty. So nvim puts in
-- its title the ways it still has a window to go -- nvim-nav=hl at the left
-- edge of a vertical split -- and the local C-h/j/k/l bindings read that from
-- #{pane_title} (modules/tmux/common.conf): a key comes here when its letter
-- is there and moves the tmux pane when it is not.
--
-- Through 'title', rather than writing the escape by hand, because nvim then
-- gives the title back when it exits or is suspended, and the shell left in
-- the pane gets its keys again.
--
-- The same title carries SpotlightDimmer's focused split (sd-nvim=..., from
-- the spotlight-dimmer plugin, set up with manage_title = false in
-- plugins/personal.lua), so the desktop dims the other splits. It goes AFTER the ways:
-- the bindings match nvim-nav=*h* against the whole title from its start, and
-- the segment holds no h/j/k/l to be mistaken for a way.
if vim.env.SSH_TTY and not vim.env.TMUX then
  local ways = ''
  local set_navigation_title = function()
    -- A float has no neighbours: keep the ways the window under it had.
    if vim.api.nvim_win_get_config(0).relative == '' then
      ways = ''
      for _, way in ipairs({ 'h', 'j', 'k', 'l' }) do
        if vim.fn.winnr(way) ~= vim.fn.winnr() then
          ways = ways .. way
        end
      end
    end
    -- Empty on a float or a search, which spotlights the whole pane
    local ok, spotlight_dimmer = pcall(require, 'spotlight-dimmer')
    local split = ok and spotlight_dimmer.title_segment() or ''
    vim.o.titlestring = 'nvim-nav=' .. ways .. (split ~= '' and ' ' .. split or '')
  end

  vim.o.title = true
  set_navigation_title()
  -- WinClosed fires while the window is still there: look once it is gone.
  -- BufWinEnter: a winbar can come or go with the buffer, moving the split.
  -- Cmdline*: the command line takes the spotlight while it is open.
  vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'WinClosed', 'WinResized', 'VimResized', 'TabEnter', 'BufWinEnter', 'CmdlineEnter', 'CmdlineLeave' }, {
    callback = function() vim.schedule(set_navigation_title) end,
  })
  -- The split moved without any of those (noice drawing its command line)
  vim.api.nvim_create_autocmd('User', {
    pattern = 'SpotlightDimmer',
    callback = set_navigation_title,
  })
end
