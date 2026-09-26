-- SQL files in VS Code, run through the mssql or pgsql extension
local vscode = require('vscode')

-- Which extension runs this buffer's queries, asked once per buffer
local function run(current_statement)
  local function execute(db_type)
    local statement = current_statement and 'runCurrentStatement' or 'runQuery'
    vscode.action(db_type .. '.' .. statement)
  end

  if vim.b.sql_db_type then return execute(vim.b.sql_db_type) end
  -- vscode-neovim shows vim.ui.select as a VS Code quick pick
  vim.ui.select({ 'SQL Server', 'PostgreSQL' }, { prompt = 'Select database type:' }, function(choice)
    if not choice then return end
    vim.b.sql_db_type = choice == 'SQL Server' and 'mssql' or 'pgsql'
    execute(vim.b.sql_db_type)
  end)
end

local function focus_result()
  if not vim.b.sql_db_type then
    return vim.api.nvim_echo({ { 'db_type not yet set. Ignoring focus on result' } }, false, {})
  end
  if vim.b.sql_db_type == 'mssql' then
    vscode.action('queryResult.focus')
  else
    vscode.action('pgQueryResult.focus')
  end
end

local function reset_db_type()
  vim.b.sql_db_type = nil
  vim.api.nvim_echo({ { 'Database type reset. Next <leader>r will prompt again.' } }, false, {})
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('VSCodeSqlFiles', { clear = true }),
  pattern = 'sql',
  callback = function(args)
    local function map(modes, lhs, rhs, desc)
      vim.keymap.set(modes, lhs, rhs, { buffer = args.buf, desc = desc })
    end
    map({ 'n', 'v' }, '<Leader>r', function() run(true) end, 'Run statement')
    map({ 'n', 'v' }, '<Leader>R', function() run(false) end, 'Run query')
    map({ 'n', 'v' }, '<Leader>j', focus_result, 'Focus results')
    map('n', '<Leader>mc', reset_db_type, 'Reset database type')
  end,
})

-- A new SQL file named after the current date and time, in
-- $DEFAULT_VSCODE_QUERY_LOCATION or else the workspace root
local function create_dated_sql_file()
  vscode.eval_async([[
    const path = await import('path');

    // Check for DEFAULT_VSCODE_QUERY_LOCATION environment variable first
    const defaultLocation = process.env.DEFAULT_VSCODE_QUERY_LOCATION;
    let targetPath;

    if (defaultLocation) {
      targetPath = defaultLocation;
    } else {
      // Fall back to workspace folder
      const workspaceFolders = vscode.workspace.workspaceFolders;
      if (!workspaceFolders || !workspaceFolders.length) {
        throw new Error('No workspace folder open');
      }
      targetPath = workspaceFolders[0].uri.fsPath;
    }

    // Generate timestamp: YYYY-MM-DD-HH-MM-SS
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const timestamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}-${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`;
    const filename = `${timestamp}.sql`;

    // Construct full file path
    const filePath = path.join(targetPath, filename);
    const fileUri = vscode.Uri.file(filePath);

    // Create empty file
    await vscode.workspace.fs.writeFile(fileUri, new Uint8Array());

    // Open file in editor
    const document = await vscode.workspace.openTextDocument(fileUri);
    await vscode.window.showTextDocument(document, { preview: false });

    return filePath;
  ]], {
    callback = function(err)
      if err then
        vim.api.nvim_echo({ { 'Error creating SQL file: ' .. err, 'ErrorMsg' } }, false, {})
      end
    end,
  })
end

-- Delete the empty SQL files those leave behind, from the same folder
local function cleanup_empty_sql_files()
  vscode.eval_async([[
    const fs = await import('fs');
    const path = await import('path');

    // Check for DEFAULT_VSCODE_QUERY_LOCATION environment variable first
    const defaultLocation = process.env.DEFAULT_VSCODE_QUERY_LOCATION;
    let targetPath;

    if (defaultLocation) {
      targetPath = defaultLocation;
    } else {
      // Fall back to workspace folder
      const workspaceFolders = vscode.workspace.workspaceFolders;
      if (!workspaceFolders || !workspaceFolders.length) {
        throw new Error('No workspace folder open');
      }
      targetPath = workspaceFolders[0].uri.fsPath;
    }

    // Read directory contents
    const entries = await fs.promises.readdir(targetPath, { withFileTypes: true });

    // Filter for .sql files only (not directories)
    const sqlFiles = entries.filter(entry =>
      entry.isFile() && entry.name.endsWith('.sql')
    );

    let deletedCount = 0;
    const deletedFiles = [];

    // Check each SQL file and delete if empty
    for (const file of sqlFiles) {
      const filePath = path.join(targetPath, file.name);
      const stats = await fs.promises.stat(filePath);

      if (stats.size === 0) {
        await fs.promises.unlink(filePath);
        deletedCount++;
        deletedFiles.push(file.name);
      }
    }

    return { count: deletedCount, files: deletedFiles };
  ]], {
    callback = function(err, result)
      -- Errors (no workspace folder, say) are ignored
      if not err and result and result.count > 0 then
        vim.api.nvim_echo({ { 'Deleted ' .. result.count .. ' empty SQL file(s)', 'Normal' } }, false, {})
      end
    end,
  })
end

vim.keymap.set('n', '<Leader>N', create_dated_sql_file, { desc = 'New SQL file (named after the date)' })

cleanup_empty_sql_files()
create_dated_sql_file()
