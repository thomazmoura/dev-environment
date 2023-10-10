-- telescope
local telescope = require('telescope')
telescope.setup {
  defaults = {
    winblend = 30
  },
  pickers = {
    find_files = {
      find_command = { 'fd', '--type', 'file', '-L', '--hidden', '--exclude', '.git', '--exclude', '.plugged' }
    },
    buffers = {
      ignore_current_buffer = true,
      sort_lastused = true,
      sort_mru = true,
    }
  },
  extensions = {
    fzf = {}
  }
}
telescope.load_extension('fzf')
telescope.load_extension('dap')
telescope.load_extension('ui-select')
