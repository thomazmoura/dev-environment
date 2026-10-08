-- Exchange e-mail in Neovim (:Paperboy inbox), my own plugin: the checkout in
-- ~/code wins when present (`dev` in config/lazy.lua), GitHub otherwise. Only
-- where $PAPERBOY_EWS_URL / $PAPERBOY_EMAIL are set (the plugin reads them itself)
return {
  {
    'thomazmoura/paperboy.nvim',
    cond = not vim.g.vscode and vim.env.PAPERBOY_EWS_URL ~= nil,
    event = 'VeryLazy',
    cmd = { 'Paperboy', 'PaperboyStatus' },
    keys = {
      { '<Leader>mi', '<cmd>Paperboy inbox<cr>', desc = 'Paperboy: inbox' },
      { '<Leader>mI', '<cmd>Paperboy all<cr>', desc = 'Paperboy: e-mails of all folders' },
      { '<Leader>mt', '<cmd>Paperboy folders<cr>', desc = 'Paperboy: folder tree' },
      { '<Leader>mc', '<cmd>Paperboy contacts<cr>', desc = 'Paperboy: contacts' },
      { '<Leader>mn', '<cmd>Paperboy compose<cr>', desc = 'Paperboy: new e-mail' },
      { '<Leader>md', '<cmd>Paperboy drafts<cr>', desc = 'Paperboy: drafts' },
    },
    opts = {
      -- Secrets in the separate "paperboy" keyring, locked again right after reading
      credential_lookup = { collection = 'paperboy' },
      compose = {
        -- Added to new e-mails, replies and forwards (Markdown; its image is
        -- embedded when sending)
        signature_file = '~/Documents/Signatures/signature.md',
        -- <Leader>ma in the compose buffer attaches a file from here
        attachment_dirs = { '~/Documents/Attachments' },
      },
    },
  },
}
