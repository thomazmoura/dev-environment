local default_global_options = { noremap = true, silent = true };
local default_buffer_options = { noremap = true, silent = true, buffer = true };

-- Vim dadbod keys
vim.keymap.set('n', '<leader>db', '<cmd>tabnew<cr><cmd>DBUI<cr>', default_global_options)
vim.keymap.set('n', '<leader>dB', '<cmd>DBUIClose<cr><cmd>tabclose<cr>', default_global_options)

-- Automatically substitute only inside selection
vim.keymap.set('v', 'S', ':s/\\%V', default_global_options)

-- Fix highlight when reloading the file (after external git checkout to another branch)
vim.keymap.set('n', '<leader>F', '<cmd>w<cr><cmd>e!<cr>', default_global_options)

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
  end
})


