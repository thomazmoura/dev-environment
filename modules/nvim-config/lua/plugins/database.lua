return {
  'kristijanhusak/vim-dadbod-ui',
  cmd = { 'DBUI', 'DBUIToggle', 'DBUIClose', 'DBUIAddConnection', 'DBUIFindBuffer' },
  dependencies = {
    {
      'tpope/vim-dadbod',
      lazy = true,
      cmd = 'DB',
      -- The encrypted store holding the SQL Server passwords, unlocked once per NeoVim
      dependencies = { 'thomazmoura/locksmith.nvim' },
      init = function()
        -- SQL Server passwords asked once and kept in locksmith (see the file)
        vim.g.db_adapter_sqlserver = 'sqlserver_locksmith#'
      end,
    },
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
    -- Completion lists everything for blink to filter (config/dadbod_fuzzy.lua), so a
    -- 200-item cap would hide the tables past the 200th
    vim.g.vim_dadbod_completion_source_limits = { tables = 5000, columns = 5000, functions = 5000, schemas = 1000 }

    -- <Leader>r runs the query (the buffer) or the selection
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('SqlKeymaps', { clear = true }),
      pattern = 'sql',
      callback = function(args)
        vim.keymap.set('n', '<Leader>r', '<Plug>(DBUI_ExecuteQuery)', { buffer = args.buf, desc = 'Run query' })
        vim.keymap.set('v', '<Leader>r', "<cmd>'<,'>DB<cr>", { buffer = args.buf, desc = 'Run selection' })
      end,
    })

    -- SQL Server results narrowed to their values, not sqlcmd's 256-character max columns
    vim.api.nvim_create_autocmd('BufReadPost', {
      group = vim.api.nvim_create_augroup('DboutCompact', { clear = true }),
      pattern = '*.dbout',
      callback = function(args) require('config.dbout_compact').compact(args.buf) end,
    })
  end,
}
