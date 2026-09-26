return {
  {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      numhl = true,
      on_attach = function(bufnr)
        local gs = require('gitsigns')
        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
        end

        -- Hunk navigation, falling back to the native ]c/[c in diff mode
        map('n', ']c', function()
          if vim.wo.diff then return vim.cmd.normal({ ']c', bang = true }) end
          gs.nav_hunk('next')
        end, 'Next hunk')
        map('n', '[c', function()
          if vim.wo.diff then return vim.cmd.normal({ '[c', bang = true }) end
          gs.nav_hunk('prev')
        end, 'Previous hunk')

        map({ 'n', 'v' }, '<Leader>Gs', ':Gitsigns stage_hunk<CR>', 'Stage hunk')
        map({ 'n', 'v' }, '<Leader>Gr', ':Gitsigns reset_hunk<CR>', 'Reset hunk')
        map('n', '<Leader>GS', gs.stage_buffer, 'Stage buffer')
        map('n', '<Leader>Gu', gs.undo_stage_hunk, 'Undo stage hunk')
        map('n', '<Leader>GR', gs.reset_buffer, 'Reset buffer')
        map('n', '<Leader>Gp', gs.preview_hunk, 'Preview hunk')
        map('n', '<Leader>Gb', function() gs.blame_line({ full = true }) end, 'Blame line')
        map('n', '<Leader>Gtb', gs.toggle_current_line_blame, 'Toggle line blame')
        map('n', '<Leader>Gd', gs.diffthis, 'Diff against index')
        map('n', '<Leader>GD', function() gs.diffthis('~') end, 'Diff against last commit')
        map('n', '<Leader>Gtd', gs.toggle_deleted, 'Toggle deleted lines')

        map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', 'Hunk')
      end,
    },
  },

  -- Also under VS Code. Not lazy: it detects the repository of every buffer.
  {
    'tpope/vim-fugitive',
    cond = true,
    lazy = false,
  },
}
