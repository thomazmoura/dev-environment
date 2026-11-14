-- Images in the terminal, Markdown copied as rich text and files opened on the device
-- I type on over SSH (xray.nvim), my own plugin: the checkout in the code folder
-- wins when present (`dev` in config/lazy.lua), GitHub otherwise. Paperboy
-- depends on it too
return {
  {
    'thomazmoura/xray.nvim',
    -- Early enough for preview.auto: plugin/xray.lua also catches the Markdown buffers
    -- already open
    event = 'VeryLazy',
    cmd = 'Xray',
    keys = {
      -- In a Markdown buffer (e-mails and compose buffers too), its previews; anywhere
      -- else, those of every buffer for the session
      { '<Leader>mv', function() require('xray.preview').toggle_current() end, desc = 'Toggle image previews' },
    },
    opts = {
      -- Image previews on as Markdown files, compose buffers and e-mails from my
      -- contacts open (others ask first)
      preview = { auto = true },
      -- Over SSH, files are served as http://dev.internal:8484/… and links to localhost
      -- open as dev.internal, which my devices reach the dev box by. Only the machine
      -- dev.internal resolves to listens on it; anywhere else the URLs stay localhost.
      -- gx (vim.ui.open) opens on the device too, over SSH
      serve = { host = 'dev.internal', ui_open = true },
    },
    init = function()
      -- <Leader>mc copies as rich text (Teams) in Markdown buffers only: elsewhere it is
      -- paperboy's calendar
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('xray_richcopy_keys', { clear = true }),
        pattern = 'markdown',
        callback = function(args)
          vim.keymap.set('n', '<Leader>mc', function() require('xray.richcopy').copy_buffer() end,
            { buffer = args.buf, silent = true, desc = 'Copy as rich text (Teams)' })
          vim.keymap.set('x', '<Leader>mc', ':Xray copy<CR>',
            { buffer = args.buf, silent = true, desc = 'Copy selection as rich text (Teams)' })
        end,
      })
    end,
  },
}
