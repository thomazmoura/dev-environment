-- git-signs settings
require 'gitsigns'.setup {
  numhl = true,
  on_attach = function(bufnr)
    local gs = package.loaded.gitsigns

    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    -- Navigation
    map('n', ']c', function()
      if vim.wo.diff then return ']c' end
      vim.schedule(function() gs.next_hunk() end)
      return '<Ignore>'
    end, {expr=true})

    map('n', '[c', function()
      if vim.wo.diff then return '[c' end
      vim.schedule(function() gs.prev_hunk() end)
      return '<Ignore>'
    end, {expr=true})

    -- Actions
    map({'n', 'v'}, '<Leader>Gs', ':Gitsigns stage_hunk<CR>')
    map({'n', 'v'}, '<Leader>Gr', ':Gitsigns reset_hunk<CR>')
    map('n', '<Leader>GS', gs.stage_buffer)
    map('n', '<Leader>Gu', gs.undo_stage_hunk)
    map('n', '<Leader>GR', gs.reset_buffer)
    map('n', '<Leader>Gp', gs.preview_hunk)
    map('n', '<Leader>Gb', function() gs.blame_line{full=true} end)
    map('n', '<leader>Gtb', gs.toggle_current_line_blame)
    map('n', '<Leader>Gd', gs.diffthis)
    map('n', '<Leader>GD', function() gs.diffthis('~') end)
    map('n', '<leader>Gtd', gs.toggle_deleted)

    -- Text object
    map({'o', 'x'}, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
  end
}

