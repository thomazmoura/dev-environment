-- gb in an html buffer opens it in the browser (config/html_preview.lua): a file as itself,
-- anything else (dadbod's cell popup, a scratch buffer) as a page with no scripts. It takes
-- over gb's :bnext from config/keymaps/common.lua, in these buffers only
vim.keymap.set('n', 'gb', function() require('config.html_preview').open_buffer(0) end,
  { buffer = true, desc = 'Open the HTML in the browser' })
