return {
  'saghen/blink.cmp',
  version = '1.*',
  event = { 'InsertEnter', 'CmdlineEnter' },
  dependencies = { 'rafamadriz/friendly-snippets' },
  opts = {
    keymap = {
      preset = 'none',
      ['<C-Space>'] = { 'show', 'show_documentation', 'hide_documentation' },
      ['<C-e>'] = { 'cancel', 'fallback' },
      ['<C-y>'] = { 'select_and_accept', 'fallback' },
      ['<CR>'] = { 'select_and_accept', 'fallback' },
      ['<Tab>'] = { 'select_next', 'snippet_forward', 'fallback' },
      ['<S-Tab>'] = { 'select_prev', 'snippet_backward', 'fallback' },
      ['<C-n>'] = { 'select_next', 'fallback' },
      ['<C-p>'] = { 'select_prev', 'fallback' },
      ['<C-d>'] = { 'scroll_documentation_up', 'fallback' },
      ['<C-u>'] = { 'scroll_documentation_down', 'fallback' },
    },
    completion = {
      -- Nothing selected until <Tab>, which inserts the item as it goes;
      -- <CR> takes the first item when none is selected
      list = { selection = { preselect = false, auto_insert = true } },
      documentation = { auto_show = true },
    },
    snippets = { preset = 'default' },
    sources = {
      default = { 'lsp', 'snippets', 'buffer', 'path' },
      per_filetype = {
        sql = { 'snippets', 'dadbod', 'buffer' },
        lua = { inherit_defaults = true, 'lazydev' },
      },
      providers = {
        dadbod = { name = 'Dadbod', module = 'vim_dadbod_completion.blink' },
        lazydev = { name = 'LazyDev', module = 'lazydev.integrations.blink', score_offset = 100 },
      },
    },
    cmdline = {
      keymap = { preset = 'cmdline' },
      completion = { menu = { auto_show = true } },
    },
  },
}
