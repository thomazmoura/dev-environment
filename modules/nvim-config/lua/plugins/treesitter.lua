-- The main branches: the archived master ones break on NeoVim 0.11+. They are
-- a rewrite that does not support lazy-loading. Tree-sitter needs a C compiler
-- and the tree-sitter CLI, so it is Linux only.
local on_linux = vim.fn.has('win32') == 0

return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    cond = on_linux and not vim.g.vscode,
    build = ':TSUpdate',
    config = function()
      local treesitter = require('nvim-treesitter')
      treesitter.setup({
        -- The default (stdpath('data')/site) is a symlink into the repo
        install_dir = vim.fn.stdpath('data') .. '/treesitter',
      })
      -- Asynchronous, and a no-op for parsers that are already installed
      treesitter.install({
        'c', 'c_sharp', 'css', 'dockerfile', 'html', 'json', 'lua', 'python',
        'regex', 'rust', 'sql', 'typescript', 'vim', 'vimdoc', 'yaml',
      })

      -- Highlighting is NeoVim's own now; pcall keeps parser-less filetypes quiet
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('TreesitterHighlight', { clear = true }),
        callback = function(args) pcall(vim.treesitter.start, args.buf) end,
      })
    end,
  },

  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    lazy = false,
    cond = on_linux and not vim.g.vscode,
    config = function()
      -- Jump forward to the next object, like targets.vim
      require('nvim-treesitter-textobjects').setup({ select = { lookahead = true } })

      local objects = {
        af = '@function.outer', ['if'] = '@function.inner',
        am = '@function.outer', im = '@function.inner',
        ac = '@class.outer', ic = '@class.inner',
        ar = '@parameter.outer', ir = '@parameter.inner',
        ak = '@block.outer', ik = '@block.inner',
      }
      for lhs, query in pairs(objects) do
        vim.keymap.set({ 'x', 'o' }, lhs, function()
          require('nvim-treesitter-textobjects.select').select_textobject(query, 'textobjects')
        end, { desc = 'Select ' .. query })
      end
    end,
  },
}
