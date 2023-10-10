require("notify").setup({
  render = "wrapped-compact",
  max_width = 200,
  timeout = 10000,
  stages = "fade_in_slide_out",
  top_down = false,
})

require("noice").setup({
  lsp = {
    -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
    override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
    },
  },
  routes = {
    {
      view = "notify",
      filter = { event = "msg_showmode" },
    },
    {
      filter = {
        event = "msg_show",
        kind = "",
        find = "written",
      },
      opts = { skip = true },
    },
  },
  views = {
    notify = {
      replace = true,
    },
  }
})

require('telescope').load_extension('noice')
