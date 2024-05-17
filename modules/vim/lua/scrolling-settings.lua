  -- I'm currently trying cinnamon as an alternative to neo-scroll (since it has more motions)

  -- neo-scroll
  --require('neoscroll').setup {
    --mappings = { '<C-u>', '<C-d>', '<C-y>', 'zt', 'zz', 'zb' },
    --easing_function = "cubic"
  --}

  require('cinnamon').setup {
    extra_keymaps = true,
    override_keymaps = true,
    extended_keymaps = true,
    centered = false,
    always_scroll = true,
    max_length = 50,
    scroll_limit = 100,
    default_delay = 2,
  }



