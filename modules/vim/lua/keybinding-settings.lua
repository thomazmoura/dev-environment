local default_global_options = { noremap = true, silent = true };
local default_buffer_options = { noremap = true, silent = true, buffer = true };

-- Simple ones
vim.keymap.set('n', '<leader>q', '<cmd>q<cr>', default_global_options)

-- QuickList
local quick_list_open = false;
local function toggleQuickList()
  if quick_list_open then
    vim.cmd('cclose')
  else
    vim.cmd('copen')
  end
  quick_list_open = not quick_list_open
end
vim.keymap.set(
  "n",
  "<Leader>Q",
  toggleQuickList,
  { desc = "Toggle quickfix list" }
)

-- Vim dadbod keys
vim.keymap.set('n', '<leader>db', '<cmd>tabnew<cr><cmd>DBUI<cr>', default_global_options)
vim.keymap.set('n', '<leader>dB', '<cmd>DBUIClose<cr><cmd>tabclose<cr>', default_global_options)

-- Automatically substitute only inside selection
vim.keymap.set('v', 'S', ':s/\\%V', default_global_options)

-- Fix highlight when reloading the file (after external git checkout to another branch)
vim.keymap.set('n', '<leader>F', '<cmd>w<cr><cmd>e!<cr>', default_global_options)

-- Quality of life improvements
vim.keymap.set('n', '<leader>N', '<cmd>enew<cr><cmd>set filetype=markdown<cr>', default_global_options)

-- Git utilities shortcuts
vim.keymap.set('n', '<leader>Gd', '<cmd>Gdiffsplit<cr>', default_global_options)
vim.keymap.set('n', '<leader>Gm', '<cmd>Gvdiffsplit!<cr><C-w>J', default_global_options)
vim.keymap.set('n', '<leader>Gb', '<cmd>Git blame<cr>', default_global_options)


-- Function to indent all @if and @else blocks that were added to Angular 17,
-- since the <leader>f is not indenting they right
local function angularFormat()
  -- Save the current cursor position
  local current_pos = vim.fn.getpos('.')

  vim.lsp.buf.format()

  -- Start from the beginning of the file
  vim.cmd('normal! gg')

  -- Loop through all occurrences of @if and @else
  local pos = vim.fn.search('@if\\|@else', 'W')
  while pos ~= 0 do
    -- Search for the next { from the current position
    local brace_pos = vim.fn.search('{', 'W')
    if brace_pos ~= 0 then
      -- Indent inside the braces
      vim.cmd('normal! >i}')
    end

    -- Continue searching for the next @if or @else after the current one
    pos = vim.fn.search('@if\\|@else', 'W')
  end

  -- Restore the cursor position
  vim.fn.setpos('.', current_pos)
  vim.cmd('normal! zz')
end

-- Create autocommand groups to ensure no duplicates
vim.api.nvim_create_augroup('HtmlIndent', { clear = true })
vim.api.nvim_create_augroup('SqlFiles', { clear = true })

-- Set up the key mapping only for .html files
vim.api.nvim_create_autocmd('FileType', {
  group = 'HtmlIndent',
  pattern = 'html',
  callback = function()
    vim.keymap.set('n', '<leader>f', angularFormat, default_buffer_options)
  end
})

-- Set up the key mapping only for sql files
vim.api.nvim_create_autocmd('FileType', {
  group = 'SqlFiles',
  pattern = 'sql',
  callback = function()
    vim.keymap.set('n', '<leader>r', '<Plug>(DBUI_ExecuteQuery)', default_buffer_options)
    vim.keymap.set('v', '<leader>r', "<cmd>'<,'>DB<cr>", default_buffer_options)
  end
})

-- Set up the key mapping only for JSON files
vim.api.nvim_create_augroup('JsonFiles', { clear = true })

local function jsonFormat()
  -- Run jq only once per buffer
  if not vim.b.json_jq_done then
    vim.cmd('%jq .')
    vim.b.json_jq_done = true
  end
  vim.lsp.buf.format()
end

vim.api.nvim_create_autocmd('FileType', {
  group = 'JsonFiles',
  pattern = {'json', 'jsonc'},
  callback = function()
    vim.keymap.set('n', '<leader>f', jsonFormat, default_buffer_options)
  end
})

-- Markview / conceal
--
-- 'conceallevel' and 'concealcursor' are window-local, not buffer-local, so when markview sets
-- them to 3/"nc" for a markdown buffer they stay behind on the window and conceal whatever comes
-- next - most visibly the quotes on JSON files. Keep the intent per buffer instead and re-apply
-- it whenever a buffer lands in a window.
local markview_filetypes = { markdown = true, quarto = true, rmd = true, typst = true }

-- Filetypes that conceal on purpose (markview's doing or their own ftplugin's) and are left alone
local concealing_filetypes = vim.tbl_extend('force', markview_filetypes, {
  help = true, man = true, rust = true, tex = true, latex = true, norg = true, org = true
})

local function applyConceal()
  if concealing_filetypes[vim.bo.filetype] then
    return
  end
  local window = vim.api.nvim_get_current_win()
  if vim.b.conceal_enabled then
    vim.wo[window].conceallevel = 3
    vim.wo[window].concealcursor = 'nc'
  else
    vim.wo[window].conceallevel = 0
    vim.wo[window].concealcursor = ''
  end
end

vim.api.nvim_create_augroup('ConcealControl', { clear = true })
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'WinEnter' }, {
  group = 'ConcealControl',
  callback = applyConceal
})

vim.keymap.set("n", "<leader>mm", function()
  if markview_filetypes[vim.bo.filetype] then
    vim.cmd('Markview splitToggle')
  else
    vim.b.conceal_enabled = not vim.b.conceal_enabled
    applyConceal()
  end
end, { desc = "Toggle Markview Split / conceal" })

-- Workhorse
local workhorse = require('workhorse')
vim.keymap.set("n", "<leader>wq", workhorse.pick_query, { desc = "Workhorse: Pick query" })
vim.keymap.set("n", "<leader>wr", workhorse.refresh, { desc = "Workhorse: Refresh" })
