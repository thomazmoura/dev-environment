-- <Tab> on a buffer or saved query in DBUI's drawer opens it in the query window, as <CR>
-- does, with the cursor kept in the drawer to go on browsing (autoload/dbui_buffers.vim)
vim.keymap.set('n', '<Tab>', function() vim.fn['dbui_buffers#preview']() end,
  { buffer = true, desc = 'Preview query' })
