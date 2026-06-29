-- Tree Sitter needs gcc or equivalent to work so it's currently only active on Linux
if not vim.env.windir then
  -- nvim-treesitter v1+ API: install parsers (runs async)
  require('nvim-treesitter').install({
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
  })

  -- Highlighting is now a core nvim feature; enable it for every filetype
  vim.api.nvim_create_autocmd('FileType', {
    pattern = '*',
    callback = function() pcall(vim.treesitter.start) end,
  })

  -- Textobjects: new plugin-level setup + explicit keymaps
  require("nvim-treesitter-textobjects").setup({
    select = { lookahead = true },
  })

  local ts_select = require("nvim-treesitter-textobjects.select")
  local function map(lhs, capture)
    vim.keymap.set({ "x", "o" }, lhs, function()
      ts_select.select_textobject(capture, "textobjects")
    end)
  end
  map("af", "@function.outer")
  map("if", "@function.inner")
  map("am", "@function.outer")
  map("im", "@function.inner")
  map("ac", "@class.outer")
  map("ic", "@class.inner")
  map("ar", "@parameter.outer")
  map("ir", "@parameter.inner")
  map("ak", "@block.outer")
  map("ik", "@block.inner")
end

