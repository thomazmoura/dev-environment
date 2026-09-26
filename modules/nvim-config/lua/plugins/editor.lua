return {
  -- File explorer. Not lazy, so that `nvim <dir>` opens it in place of netrw.
  {
    'nvim-tree/nvim-tree.lua',
    lazy = false,
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    keys = {
      { '<C-e>', '<cmd>NvimTreeToggle<cr>', desc = 'File explorer' },
      { '<Leader>e', '<cmd>NvimTreeToggle<cr>', desc = 'File explorer' },
      { '<Leader>E', '<cmd>NvimTreeFocus<cr>', desc = 'Focus file explorer' },
      { '<Leader><C-e>', '<cmd>NvimTreeFindFile<cr>', desc = 'Reveal file in explorer' },
    },
    opts = {
      update_focused_file = { enable = true, update_root = false },
      -- Too slow on large trees
      diagnostics = { enable = false },
      actions = {
        open_file = { window_picker = { enable = false } },
      },
      view = { width = 50 },
    },
  },

  {
    'mbbill/undotree',
    keys = {
      { '<Leader>u', '<cmd>UndotreeToggle<cr><cmd>UndotreeFocus<cr>', desc = 'Undo tree' },
    },
  },

  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = function()
      local function harpoon() return require('harpoon') end
      local function list() return harpoon():list() end
      local keys = {
        { '<M-h>', function() harpoon().ui:toggle_quick_menu(list()) end, desc = 'Harpoon menu' },
        { '<Leader>hm', function() list():add() end, desc = 'Harpoon: mark file' },
        { '<Leader>hd', function() list():clear() end, desc = 'Harpoon: clear marks' },
        { '<Leader>hn', function() list():next() end, desc = 'Harpoon: next' },
        { '<Leader>hN', function() list():prev() end, desc = 'Harpoon: previous' },
      }
      -- Alt+key jumps to a slot, Alt+Shift+key puts the current file in it
      local slots = { { 'j', 'J' }, { 'k', 'K' }, { 'l', 'L' }, { ';', ':' }, { 'u', 'U' }, { 'i', 'I' }, { 'o', 'O' }, { 'p', 'P' } }
      for index, slot in ipairs(slots) do
        local jump, set = slot[1], slot[2]
        local set_lhs = set == ':' and '<M-:>' or '<M-S-' .. set .. '>'
        table.insert(keys, { '<M-' .. jump .. '>', function() list():select(index) end, desc = 'Harpoon: file ' .. index })
        table.insert(keys, { set_lhs, function() list():replace_at(index) end, desc = 'Harpoon: set file ' .. index })
      end
      return keys
    end,
    config = function()
      require('harpoon'):setup()
    end,
  },

  {
    'smoka7/hop.nvim',
    keys = {
      { 'gj', function() require('hop').hint_char1({ inclusive_jump = false }) end, desc = 'Hop to char' },
      { 'gj', function() require('hop').hint_char1({ inclusive_jump = true }) end, mode = { 'x', 'o' }, desc = 'Hop to char' },
      { 'gJ', function() require('hop').hint_char1({ inclusive_jump = false }) end, mode = { 'n', 'x', 'o' }, desc = 'Hop before char' },
      { '<Leader>j', '<cmd>HopLineStartAC<cr>', desc = 'Hop to line below' },
      { '<Leader>k', '<cmd>HopLineStartBC<cr>', desc = 'Hop to line above' },
    },
    opts = {},
  },

  {
    'thomazmoura/auto-save.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    opts = {
      enabled = true,
      trigger_events = { 'BufLeave' },
    },
  },

  -- Case conversion (<Leader>s + p/c/_/-/u/...)
  {
    'arthurxavierx/vim-caser',
    event = 'VeryLazy',
    init = function()
      vim.g.caser_prefix = '<Leader>s'
    end,
  },

  -- Text objects (also under VS Code)
  {
    'wellle/targets.vim',
    cond = true,
    event = 'VeryLazy',
    init = function()
      -- Keep NeoVim's own tag and angle-bracket objects
      vim.api.nvim_create_autocmd('User', {
        pattern = 'targets#mappings#user',
        callback = function()
          vim.fn['targets#mappings#extend']({ t = vim.empty_dict(), ['<'] = vim.empty_dict(), ['>'] = vim.empty_dict() })
        end,
      })
    end,
  },
  {
    'kylechui/nvim-surround',
    cond = true,
    event = 'VeryLazy',
  },
  { 'tpope/vim-repeat', cond = true, event = 'VeryLazy' },
  { 'tpope/vim-eunuch', cond = true, event = 'VeryLazy' },

  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    opts = {},
  },
}
