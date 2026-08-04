-- Tree Sitter needs gcc or equivalent to work so it's currently only active on Linux
if vim.env.windir then
  return
end

require('nvim-treesitter').setup {
  -- stdpath('data')/site is a symlink to modules/vim in the dev-environment repo
  -- (see LinuxDevEnv/host-setup.sh), so the default install_dir would compile
  -- parsers straight into the git worktree.
  install_dir = vim.fn.stdpath('data') .. '/treesitter',
}

-- Asynchronous, and a no-op for parsers that are already installed.
require('nvim-treesitter').install {
  "c",
  "c_sharp",
  "css",
  "dockerfile",
  "html",
  "json",
  "lua",
  "python",
  "regex",
  "rust",
  "sql",
  "typescript",
  "vim",
  "vimdoc",
  "yaml",
}

-- Highlighting belongs to Neovim now rather than to the plugin (see
-- :h treesitter-highlight). pcall keeps filetypes without a parser quiet, which
-- is what the old `highlight.disable = {}` behaviour amounted to.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('TreesitterHighlight', { clear = true }),
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})

require('nvim-treesitter-textobjects').setup {
  select = {
    -- Automatically jump forward to textobj, similar to targets.vim
    lookahead = true,
  },
}

-- Capture groups defined in textobjects.scm. On the main branch these are plain
-- keymaps rather than a `keymaps` config table.
local textobjects = {
  ["af"] = "@function.outer",
  ["if"] = "@function.inner",
  ["am"] = "@function.outer",
  ["im"] = "@function.inner",
  ["ac"] = "@class.outer",
  ["ic"] = "@class.inner",
  ["ar"] = "@parameter.outer",
  ["ir"] = "@parameter.inner",
  ["ak"] = "@block.outer",
  ["ik"] = "@block.inner",
}

for mapping, query in pairs(textobjects) do
  vim.keymap.set({ "x", "o" }, mapping, function()
    require('nvim-treesitter-textobjects.select').select_textobject(query, "textobjects")
  end, { desc = "Select " .. query })
end
