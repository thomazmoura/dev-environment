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
      -- A space shows the menu only after a join's ON, for its conditions (config/sql_join.lua),
      -- and in sql buffers a '(' only after INSERT INTO <table>, for its columns (config/sql_insert.lua)
      trigger = {
        show_on_blocked_trigger_characters = function()
          if require('config.sql_join').after_on() then return { '\n', '\t' } end
          if vim.bo.filetype == 'sql' and not require('config.sql_insert').after_insert() then
            return { ' ', '\n', '\t', '(' }
          end
          return { ' ', '\n', '\t' }
        end,
      },
    },
    snippets = { preset = 'default' },
    sources = {
      default = { 'lsp', 'snippets', 'buffer', 'path' },
      per_filetype = {
        sql = { 'sql_join', 'sql_insert', 'snippets', 'dadbod', 'buffer' },
        lua = { inherit_defaults = true, 'lazydev' },
      },
      providers = {
        -- Also completes modules/az and mod without a leading ./
        path = { module = 'config.bare_path' },
        -- Tables and columns filtered fuzzily, not only by their start
        dadbod = { name = 'Dadbod', module = 'config.dadbod_fuzzy' },
        -- A join's ON completed from the foreign keys, ahead of everything else
        sql_join = { name = 'Join', module = 'config.sql_join', score_offset = 100 },
        -- An INSERT's column list completed with all the table's columns, first too
        sql_insert = { name = 'Insert', module = 'config.sql_insert', score_offset = 100 },
        lazydev = { name = 'LazyDev', module = 'lazydev.integrations.blink', score_offset = 100 },
      },
    },
    cmdline = {
      keymap = { preset = 'cmdline' },
      -- cmdline has its own defaults (preselect = true), so mirror insert mode:
      -- the first <Tab> selects the first item instead of skipping it
      completion = {
        menu = { auto_show = true },
        list = { selection = { preselect = false, auto_insert = true } },
      },
    },
  },
}
