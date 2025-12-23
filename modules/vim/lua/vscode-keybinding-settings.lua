local vscode = require('vscode')
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

-- Check if running VS Code Insiders
local function is_vscode_insiders()
  local success, result = pcall(function()
    return vscode.eval([[
      return vscode.env.appName.toLowerCase().includes('insiders') ||
             vscode.version.toLowerCase().includes('insider')
    ]])
  end)

  if not success then
    print("Error checking VS Code version: " .. tostring(result))
    return false
  end

  return result
end

-- Create new SQL file with current date and time as filename
local function create_dated_sql_file()
  vscode.eval_async([[
    const path = await import('path');

    // Check if workspace folder exists
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders || !workspaceFolders.length) {
      throw new Error('No workspace folder open');
    }

    const workspacePath = workspaceFolders[0].uri.fsPath;

    // Generate timestamp: YYYY-MM-DD-HH-MM-SS
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const timestamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}-${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`;
    const filename = `${timestamp}.sql`;

    // Construct full file path
    const filePath = path.join(workspacePath, filename);
    const fileUri = vscode.Uri.file(filePath);

    // Create empty file
    await vscode.workspace.fs.writeFile(fileUri, new Uint8Array());

    // Open file in editor
    const document = await vscode.workspace.openTextDocument(fileUri);
    await vscode.window.showTextDocument(document, { preview: false });

    return filePath;
  ]], {
    callback = function(err, filePath)
      if err then
        vim.api.nvim_echo({{"Error creating SQL file: " .. err, "ErrorMsg"}}, false, {})
      end
    end
  })
end

-- Create new untitled markdown file
local function create_untitled_markdown()
  vscode.eval_async([[
    // Create new untitled file
    await vscode.commands.executeCommand('workbench.action.files.newUntitledFile');

    // Set language to markdown
    await vscode.languages.setTextDocumentLanguage(
      vscode.window.activeTextEditor.document,
      'markdown'
    );
  ]], {
    callback = function(err)
      if err then
        vim.api.nvim_echo({{"Error creating markdown file: " .. err, "ErrorMsg"}}, false, {})
      end
    end
  })
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

-- <leader>N handler: Create SQL file in Insiders, markdown in Stable
local function handle_leader_n()
  if is_vscode_insiders() then
    create_dated_sql_file()
  else
    create_untitled_markdown()
  end
end

vim.keymap.set('n', '<leader>N', handle_leader_n, {
  noremap = true,
  silent = true,
  desc = "Create new file (SQL in Insiders, Markdown in Stable)"
})
