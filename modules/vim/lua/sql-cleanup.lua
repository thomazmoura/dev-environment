local vscode = require('vscode')

-- Check if running VS Code Insiders
local function is_vscode_insiders()
  local success, result = pcall(function()
    return vscode.eval([[
      return vscode.env.appName.toLowerCase().includes('insiders') ||
             vscode.version.toLowerCase().includes('insider')
    ]])
  end)

  if not success then
    return false
  end

  return result
end

-- Cleanup empty SQL files in workspace root
local function cleanup_empty_sql_files()
  vscode.eval_async([[
    const fs = await import('fs');
    const path = await import('path');

    // Check if workspace folder exists
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders || !workspaceFolders.length) {
      throw new Error('No workspace folder open');
    }

    const workspacePath = workspaceFolders[0].uri.fsPath;

    // Read directory contents
    const entries = await fs.promises.readdir(workspacePath, { withFileTypes: true });

    // Filter for .sql files only (not directories)
    const sqlFiles = entries.filter(entry =>
      entry.isFile() && entry.name.endsWith('.sql')
    );

    let deletedCount = 0;
    const deletedFiles = [];

    // Check each SQL file and delete if empty
    for (const file of sqlFiles) {
      const filePath = path.join(workspacePath, file.name);
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
      if err then
        -- Silently ignore errors (e.g., no workspace folder)
        -- vim.api.nvim_echo({{"Error cleaning up SQL files: " .. err, "ErrorMsg"}}, false, {})
      elseif result and result.count > 0 then
        -- Optionally notify user of cleanup (commented out for silent operation)
        vim.api.nvim_echo({{"Deleted " .. result.count .. " empty SQL file(s)", "Normal"}}, false, {})
      end
    end
  })
end

-- Auto-execute cleanup on module load if running VSCode Insiders
if is_vscode_insiders() then
  cleanup_empty_sql_files()
end
