return {
  'nvim-telescope/telescope.nvim',
  version = '0.2.*',
  cmd = 'Telescope',
  dependencies = {
    'nvim-lua/plenary.nvim',
    { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    'nvim-telescope/telescope-ui-select.nvim',
    'nvim-telescope/telescope-dap.nvim',
  },
  -- ui-select replaces vim.ui.select, so it has to be there before the first
  -- code action rather than on the first :Telescope
  event = 'VeryLazy',
  keys = {
    { '<Leader>/', '<cmd>Telescope find_files<cr>', desc = 'Find files' },
    { '<C-p>', '<cmd>Telescope find_files<cr>', desc = 'Find files' },
    { '<Leader>*', '<cmd>Telescope live_grep<cr>', desc = 'Grep' },
    { '<C-f>', '<cmd>Telescope live_grep<cr>', desc = 'Grep' },
    { '<Leader>?', '<cmd>Telescope buffers<cr>', desc = 'Buffers' },
    { '<Leader><C-p>', '<cmd>Telescope buffers<cr>', desc = 'Buffers' },
    { '<Leader>h', '<cmd>Telescope help_tags<cr>', desc = 'Help' },
    { '<Leader>,', '<cmd>Telescope find_files cwd=~/code/dotfiles<cr>', desc = 'Find dotfiles' },
  },
  config = function()
    local find_command = { 'fd', '--type', 'file', '-L', '--hidden', '--exclude', '.git' }
    if vim.env.FZF_IGNORE_FOLDER then
      vim.list_extend(find_command, { '--exclude', vim.env.FZF_IGNORE_FOLDER })
    end

    local telescope = require('telescope')
    telescope.setup({
      defaults = { winblend = 30 },
      pickers = {
        find_files = { find_command = find_command },
        buffers = { ignore_current_buffer = true, sort_lastused = true, sort_mru = true },
      },
      extensions = { fzf = {} },
    })
    for _, extension in ipairs({ 'fzf', 'ui-select', 'dap', 'noice' }) do
      pcall(telescope.load_extension, extension)
    end
  end,
}
