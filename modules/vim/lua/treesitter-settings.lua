-- Tree Sitter needs gcc or equivalent to work so it's currently only active on Linux
if not vim.env.windir then
  require'nvim-treesitter.configs'.setup {
    -- A list of parser names, or "all" for possible list, check: https://github.com/nvim-treesitter/nvim-treesitter#supported-languages
    ensure_installed = {
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
    },

    -- Install parsers synchronously (only applied to `ensure_installed`)
    sync_install = false,

    -- List of parsers to ignore installing (for "all")
    ignore_install = { },

    highlight = {
      -- `false` will disable the whole extension
      enable = true,

      -- NOTE: these are the names of the parsers and not the filetype. (for example if you want to disable highlighting for the `tex` filetype, you need to include `latex` in this list as this is the name of the parser)
      -- list of language that will be disabled
      disable = { },

      -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
      -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
      -- Using this option may slow down your editor, and you may see some duplicate highlights.
      -- Instead of true it can also be a list of languages
      additional_vim_regex_highlighting = false,
    },
  }

  require'nvim-treesitter.configs'.setup {
    textobjects = {
      select = {
        enable = true,
        -- Automatically jump forward to textobj, similar to targets.vim
        lookahead = true,
        keymaps = {
          -- You can use the capture groups defined in textobjects.scm
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
        },
      },
    },
  }
end

