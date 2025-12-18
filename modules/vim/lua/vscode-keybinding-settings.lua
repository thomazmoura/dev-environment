local default_buffer_options = { noremap = true, silent = true, buffer = true }

-- SQL Query Runner - per-buffer database type selection
local function run_sql_query()
  local db_type = vim.b.sql_db_type

  if not db_type then
    vim.api.nvim_echo({{"Database: (s)ql server / (p)ostgres", "Question"}}, false, {})
    local char = vim.fn.getcharstr()
    vim.cmd('redraw')

    if char:lower() == 's' then
      vim.b.sql_db_type = 'mssql'
    elseif char:lower() == 'p' then
      vim.b.sql_db_type = 'pgsql'
    else
      vim.api.nvim_echo({{"Invalid choice. Use 's' or 'p'.", "ErrorMsg"}}, false, {})
      return
    end
    db_type = vim.b.sql_db_type
  end

  if db_type == 'mssql' then
    vim.fn.VSCodeNotify('mssql.runCurrentStatement')
  else
    vim.fn.VSCodeNotify('pgsql.runCurrentStatement')
  end
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
    vim.keymap.set('n', '<leader>r', run_sql_query, default_buffer_options)
    vim.keymap.set('n', '<leader>mc', reset_sql_db_type, default_buffer_options)
  end
})
