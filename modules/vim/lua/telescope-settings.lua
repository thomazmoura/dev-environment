-- telescope
require('telescope').setup {
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
    fzf = { }
  }
}

require('telescope').load_extension('fzf', 'dap')

