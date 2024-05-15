-- Define the Lua function
local function indent_angular_if_else_blocks()
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
end

-- Create an autocommand group to ensure no duplicates
vim.api.nvim_create_augroup('HtmlIndent', { clear = true })

-- Set up the key mapping only for .html files
vim.api.nvim_create_autocmd('FileType', {
  group = 'HtmlIndent',
  pattern = 'html',
  callback = function()
    vim.keymap.set('n', '<leader>>', indent_angular_if_else_blocks, { noremap = true, silent = true, buffer = true })
  end
})

