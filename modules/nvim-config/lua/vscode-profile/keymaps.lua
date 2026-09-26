local vscode = require('vscode')
local map = vim.keymap.set

-- Normal-mode keymap that runs a VS Code command
local function action(lhs, command, desc)
  map('n', lhs, function() vscode.action(command) end, { desc = desc })
end

-- Folds
action('zc', 'editor.fold')
action('zC', 'editor.foldRecursively')
action('zo', 'editor.unfold')
action('zO', 'editor.unfoldRecursively')
action('zM', 'editor.foldAll')
action('zR', 'editor.unfoldAll')

-- Editor
action('K', 'editor.action.showHover')
action('gK', 'editor.debug.action.showDebugHover')
action('gH', 'editor.debug.action.showDebugHover')
action('gi', 'editor.action.goToImplementation')
action('gr', 'editor.action.goToReferences')
action('<Leader><Leader>', 'workbench.action.files.save')
action('<Leader>w', 'workbench.action.files.save')
action('<Leader>.', 'editor.action.quickFix')
action('<Leader>x', 'workbench.action.closeActiveEditor')
action('<Leader>f', 'editor.action.formatDocument')
action('<Leader>F', 'editor.action.formatChanges')
action('<Leader>h', 'editor.action.wordHighlight.trigger')
action('<Leader>o', 'outline.focus')
action('<Leader>e', 'workbench.view.explorer')
action('<Leader><CR>', 'workbench.action.keepEditor')
action('<Leader><Esc>', 'notifications.clearAll')
action('<Leader>R', 'workbench.action.reloadWindow')

-- Comments
action('<Leader>c<Leader>', 'editor.action.commentLine')
action('<Leader>cc', 'editor.action.addCommentLine')
action('<Leader>cu', 'editor.action.removeCommentLine')

-- Tests
action('<Leader>t', 'dotnet.test.runTestsInContext')
action('<Leader>d', 'dotnet.test.debugTestsInContext')

-- Editors and editor groups
action('<Leader><Tab>', 'workbench.action.openPreviousRecentlyUsedEditor')
action('<Leader><S-Tab>', 'workbench.action.openNextRecentlyUsedEditor')
action('<Leader>/', 'workbench.action.quickOpen')
action('<Leader>?', 'workbench.action.quickOpen')
action('<C-h>', 'workbench.action.focusLeftGroup')
action('<C-l>', 'workbench.action.focusRightGroup')
action('<C-j>', 'workbench.action.focusBelowGroup')
action('<C-k>', 'workbench.action.focusAboveGroup')
map('n', 'gb', 'gt', { remap = true, desc = 'Next editor' })
map('n', 'gB', 'gT', { remap = true, desc = 'Previous editor' })

-- Problems
action(']q', 'editor.action.marker.nextInFiles')
action('[q', 'editor.action.marker.prevInFiles')

map('n', '<Esc>', '<cmd>nohlsearch<cr>', { desc = 'Clear highlights' })

-- GUIDs through pwsh, which is there on Windows too
map('n', '<Leader>gg', [[mz<cmd>r!pwsh -NoProfile -C "(New-Guid).Guid"<cr>y$dd`z"0p]], { desc = 'Insert GUID' })
map('n', '<Leader>gG', [[mz<cmd>r!pwsh -NoProfile -C "(New-Guid).Guid"<cr>y$dd`z"0P]], { desc = 'Insert GUID before' })
