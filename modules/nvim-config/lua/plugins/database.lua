return {
  'kristijanhusak/vim-dadbod-ui',
  cmd = { 'DBUI', 'DBUIToggle', 'DBUIClose', 'DBUIAddConnection', 'DBUIFindBuffer' },
  dependencies = {
    { 'tpope/vim-dadbod', lazy = true, cmd = 'DB' },
    { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
  },
  keys = {
    { '<Leader>db', '<cmd>tabnew<cr><cmd>DBUI<cr>', desc = 'Database UI' },
    { '<Leader>dB', '<cmd>DBUIClose<cr><cmd>tabclose<cr>', desc = 'Close database UI' },
  },
  init = function()
    vim.g.db_ui_save_location = '~/.shared/sql-saved-queries'
    vim.g.db_ui_tmp_query_location = '~/.shared/sql-queries'
    vim.g.db_ui_use_nvim_notify = 1
    vim.g.db_ui_execute_on_save = 0
    vim.g.db_ui_show_database_icon = 1
    vim.g.db_ui_use_nerd_fonts = 1

    -- <Leader>r runs the query (the buffer) or the selection
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('SqlKeymaps', { clear = true }),
      pattern = 'sql',
      callback = function(args)
        vim.keymap.set('n', '<Leader>r', '<Plug>(DBUI_ExecuteQuery)', { buffer = args.buf, desc = 'Run query' })
        vim.keymap.set('v', '<Leader>r', "<cmd>'<,'>DB<cr>", { buffer = args.buf, desc = 'Run selection' })
      end,
    })
  end,
}
