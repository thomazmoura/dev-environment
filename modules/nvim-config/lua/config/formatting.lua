-- Filetype-specific <Leader>f; plugins/lsp.lua leaves these alone
local function buffer_map(filetypes, rhs, name)
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup(name, { clear = true }),
    pattern = filetypes,
    callback = function(args)
      vim.keymap.set('n', '<Leader>f', rhs, { buffer = args.buf, desc = 'Format' })
    end,
  })
end

-- JSON: pretty-print with jq the first time (minified files), then the LSP.
-- jq refuses comments, so on failure the buffer is left for the LSP alone.
buffer_map({ 'json', 'jsonc' }, function()
  if not vim.b.json_jq_done then
    vim.b.json_jq_done = true
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local result = vim.system({ 'jq', '.' }, { stdin = lines, text = true }):wait()
    if result.code == 0 then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.trim(result.stdout), '\n'))
    end
  end
  vim.lsp.buf.format()
end, 'JsonFormat')

-- Angular templates: the LSP formats, but leaves the @if/@else blocks of
-- Angular 17's control flow unindented, so indent inside their braces
buffer_map('html', function()
  local view = vim.fn.winsaveview()
  vim.lsp.buf.format()
  vim.cmd('normal! gg')
  while vim.fn.search([[@if\|@else]], 'W') ~= 0 do
    if vim.fn.search('{', 'W') ~= 0 then
      vim.cmd('normal! >i}')
    end
  end
  vim.fn.winrestview(view)
  vim.cmd('normal! zz')
end, 'AngularFormat')
