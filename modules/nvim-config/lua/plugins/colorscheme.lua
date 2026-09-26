return {
  'folke/tokyonight.nvim',
  lazy = false,
  priority = 1000,
  opts = {
    style = 'storm',
    on_highlights = function(hl)
      local function set(group, attrs)
        hl[group] = vim.tbl_extend('force', hl[group] or {}, attrs)
      end
      -- The terminal's background shows through (see config/pane_background.lua
      -- for the Termux exception)
      set('Normal', { bg = 'NONE' })
      set('NormalNC', { bg = 'NONE' })
      set('NvimTreeNormal', { bg = 'NONE' })
      set('NvimTreeNormalNC', { bg = 'NONE' })
      set('NvimTreeWinSeparator', { bg = 'NONE', fg = '#414868' })
      set('VertSplit', { bg = 'NONE', fg = '#414868' })
      -- ...but not behind the command line and the numbers
      set('MsgArea', { bg = '#1a1b26' })
      set('LineNr', { bg = '#1a1b26' })
      set('LineNrAbove', { fg = '#777777' })
      set('LineNrBelow', { fg = '#777777' })
      -- Easier to read comments and faded text
      set('Comment', { fg = '#819c98' })
      set('JsonCommentError', { fg = '#819c98' })
      set('DiagnosticUnnecessary', { fg = '#818181' })
      set('CopilotSuggestion', { fg = '#989898' })
    end,
  },
  config = function(_, opts)
    require('tokyonight').setup(opts)
    vim.cmd.colorscheme('tokyonight-storm')
  end,
}
