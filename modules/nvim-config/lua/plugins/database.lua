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
        -- SQL Server and Postgres passwords asked once and kept in locksmith
        -- (config/dadbod_locksmith.lua)
        vim.g.db_adapter_sqlserver = 'sqlserver_locksmith#'
        vim.g.db_adapter_postgresql = 'postgresql_locksmith#'
        -- postgres: URLs too, which dadbod-ui would otherwise give dadbod's own adapter
        vim.g.db_adapter_postgres = 'postgresql_locksmith#'
      end,
    },
    { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
  },
  keys = {
    -- Only once locksmith, where the passwords are, is unlocked (config/dadbod_locksmith.lua)
    { '<Leader>db', '<cmd>DatabaseUI<cr>', desc = 'Database UI' },
    { '<Leader>dB', '<cmd>DBUIClose<cr><cmd>tabclose<cr>', desc = 'Close database UI' },
  },
  init = function()
    -- <Leader>db, and the tmux picker's "DadBod (database)" pane (nvim -c DatabaseUI,
    -- tmux/scripts/tmux-helpers.sh): DBUI in a new tab once locksmith is unlocked
    vim.api.nvim_create_user_command('DatabaseUI', function() require('config.dadbod_locksmith').open_ui() end,
      { desc = 'Database UI, once locksmith is unlocked' })

    vim.g.db_ui_save_location = '~/.shared/sql-saved-queries'
    vim.g.db_ui_tmp_query_location = '~/.shared/sql-queries'
    vim.g.db_ui_use_nvim_notify = 1
    vim.g.db_ui_execute_on_save = 0
    vim.g.db_ui_show_database_icon = 1
    vim.g.db_ui_use_nerd_fonts = 1
    -- Completion lists everything for blink to filter (config/dadbod_fuzzy.lua), so a
    -- 200-item cap would hide the tables past the 200th
    vim.g.vim_dadbod_completion_source_limits = { tables = 5000, columns = 5000, functions = 5000, schemas = 1000 }

    -- <Leader>r runs the statement under the cursor (config/sql_statement.lua) or the
    -- selection, <Leader>R the whole buffer, as in the VS Code profile
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('SqlKeymaps', { clear = true }),
      pattern = 'sql',
      callback = function(args)
        vim.keymap.set('n', '<Leader>r', function() require('config.sql_statement').run() end,
          { buffer = args.buf, desc = 'Run statement' })
        vim.keymap.set('n', '<Leader>R', '<Plug>(DBUI_ExecuteQuery)', { buffer = args.buf, desc = 'Run query' })
        -- A : from visual mode, not <cmd>: the '<,'> marks are only set on leaving it, so
        -- <cmd> would run the previous selection
        vim.keymap.set('v', '<Leader>r', ':DB<cr>', { buffer = args.buf, desc = 'Run selection' })
        -- One of the buffer's earlier results, in the results window (config/dbout_history.lua)
        vim.keymap.set('n', '<Leader>d?', function() require('config.dbout_history').pick() end,
          { buffer = args.buf, desc = 'Results history' })
        require('config.sql_completion_triggers').attach(args.buf)
      end,
    })

    -- Results laid out as framed columns narrowed to their values (config/dbout_compact.lua):
    -- SQL Server's, not sqlcmd's 256-character max columns, and Postgres's, not psql's table
    vim.api.nvim_create_autocmd('BufReadPost', {
      group = vim.api.nvim_create_augroup('DboutCompact', { clear = true }),
      pattern = '*.dbout',
      callback = function(args) require('config.dbout_compact').compact(args.buf) end,
    })

    -- Each query buffer keeps its results, and the results window follows the buffer entered
    -- (config/dbout_history.lua). Here, not in config: :DB runs before dadbod-ui loads
    require('config.dbout_history').setup()
  end,
}
