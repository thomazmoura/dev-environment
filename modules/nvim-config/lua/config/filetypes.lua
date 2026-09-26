vim.filetype.add({
  extension = {
    ['code-snippets'] = 'json',
    tsx = 'typescript',
    jsx = 'typescript',
    config = 'xml',
    csproj = 'xml',
  },
})

-- Comments in JSON are the rule rather than the exception (tsconfig,
-- appsettings, VS Code settings), so every json buffer is treated as jsonc
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('JsonToJsonc', { clear = true }),
  pattern = 'json',
  callback = function() vim.bo.filetype = 'jsonc' end,
})
