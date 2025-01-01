-- telescope

-- Build the find_command array dynamically
local find_command = { 'fd', '--type', 'file', '-L', '--hidden', '--exclude', '.git', '--exclude', '.plugged' }
if vim.env.FZF_IGNORE_FOLDER then
    table.insert(find_command, '--exclude')
    table.insert(find_command, vim.env.FZF_IGNORE_FOLDER)
end
local telescope = require('telescope')
telescope.setup {
  defaults = {
    winblend = 30
  },
  pickers = {
    find_files = {
      find_command = find_command
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
