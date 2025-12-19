local default_buffer_options = { noremap = true, silent = true, buffer = true }

-- Helper to execute the SQL command based on db type
local function execute_sql_command(db_type, currentOnly)
  if db_type == 'mssql' then
    if currentOnly == true then
      vim.fn.VSCodeNotify('mssql.runCurrentStatement')
    else
      vim.fn.VSCodeNotify('mssql.runQuery')
    end
  else
    if currentOnly == true then
      vim.fn.VSCodeNotify('pgsql.runCurrentStatement')
    else
      vim.fn.VSCodeNotify('pgsql.runQuery')
    end
  end
end

-- SQL Query Runner - per-buffer database type selection
local function run_sql_query(currentOnly)
  local db_type = vim.b.sql_db_type

  if db_type then
    execute_sql_command(db_type, currentOnly)
    return
  end

  -- Use vim.ui.select which VSCode-Neovim shows as VS Code's quick pick
  vim.ui.select(
    { 'SQL Server', 'PostgreSQL' },
    { prompt = 'Select database type:' },
    function(choice)
      if choice == 'SQL Server' then
        vim.b.sql_db_type = 'mssql'
      elseif choice == 'PostgreSQL' then
        vim.b.sql_db_type = 'pgsql'
      else
        return -- User cancelled
      end
      execute_sql_command(vim.b.sql_db_type, currentOnly)
    end
  )
end

local function run_current_sql_query()
  run_sql_query(true)
end

local function run_full_sql_query()
  run_sql_query(false)
end

-- Reset database type for current buffer
local function reset_sql_db_type()
  vim.b.sql_db_type = nil
  vim.api.nvim_echo({{"Database type reset. Next <leader>r will prompt again.", "Normal"}}, false, {})
end

-- Create autocommand group
vim.api.nvim_create_augroup('VSCodeSqlFiles', { clear = true })

-- Set up key mappings only for sql files
vim.api.nvim_create_autocmd('FileType', {
  group = 'VSCodeSqlFiles',
  pattern = 'sql',
  callback = function()
    vim.keymap.set({'n', 'v'}, '<leader>r', run_current_sql_query, default_buffer_options)
    vim.keymap.set({'n', 'v'}, '<leader>R', run_full_sql_query, default_buffer_options)
    vim.keymap.set('n', '<leader>mc', reset_sql_db_type, default_buffer_options)
  end
})
