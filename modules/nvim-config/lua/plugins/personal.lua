-- Plugins of my own
local spotlight_checkout = vim.fn.expand('~/code/spotlight-dimmer')
local spotlight_subdir = 'SpotlightDimmer.NeovimPlugin'
local spotlight_local = vim.uv.fs_stat(spotlight_checkout .. '/' .. spotlight_subdir) ~= nil

return {
  -- Azure DevOps work items
  {
    'thomazmoura/workhorse.nvim',
    cmd = 'Workhorse',
    keys = function()
      local keys = {
        { '<Leader>wq', function() require('workhorse').pick_query() end, desc = 'Workhorse: pick query' },
        { '<Leader>wr', function() require('workhorse').refresh() end, desc = 'Workhorse: refresh' },
      }
      local queries = {
        wT = '0ce03ce4-34b3-417b-a7d7-928d45a970dc', -- Tree
        wt = 'a7977848-adab-4453-a4cf-39c28163ac3c', -- Tree
        wu = '729b31ef-3bce-4fcb-b300-0342e4ce69c8', -- User Stories
        wf = '38cfedab-c989-41bb-9d28-71d2c4ad9464', -- Features
        we = '7c0761cd-ba78-4769-a28e-68685934d0aa', -- Epics
        wl = 'd53e77f7-d7c8-49ff-ba14-35a061d047e9', -- LuaLine
        wa = '3c82101c-2a67-408f-9fd7-8ad00a55710c', -- Full (All)
        wx = '9a90e30d-0827-4fe9-9426-e70a8fd62ca6', -- Trash
      }
      for lhs, id in pairs(queries) do
        table.insert(keys, { '<Leader>' .. lhs, '<cmd>Workhorse query ' .. id .. '<cr>', desc = 'Workhorse query' })
      end
      return keys
    end,
    opts = {
      project = 'GTI',
      team = 'Equipe ArquiteturaNET',
      grouping_mode = 'board_column',
      default_board = 'Stories',
      default_work_item_type = 'User Story',
      default_area_path = 'GTI\\ArquiteturaNET',
      deleted_state = 'Removed',
      available_states = {
        ['Epic'] = { 'New', 'Active', 'Resolved', 'Closed', 'Removed' },
        ['Feature'] = { 'New', 'Active', 'Resolved', 'Closed', 'Removed' },
        ['User Story'] = { 'New', 'Active', 'Resolved', 'Closed', 'Removed' },
        ['Bug'] = { 'New', 'Active', 'Resolved', 'Closed' },
        ['Task'] = { 'New', 'Active', 'Closed' },
      },
      state_colors = {
        ['New'] = 'Special',
        ['Active'] = 'Function',
        ['Resolved'] = 'Identifier',
        ['Closed'] = 'LspCodeLens',
        ['Removed'] = 'Debug',
      },
      column_colors = {
        ['Em Andamento'] = 'Function',
        ['A Ser Feito'] = 'DiagnosticHint',
        ['Backlog'] = 'Special',
        ['Bloqueado'] = 'ErrorMsg',
        ['Feito'] = 'Identifier',
        ['Homologação'] = 'Debug',
        ['Entregue'] = 'LspCodeLens',
        ['New'] = 'Special',
      },
      column_order = {
        'Em Andamento', 'Bloqueado', 'A Ser Feito', 'Homologação',
        'Feito', 'Backlog', 'New', 'Entregue',
      },
      column_sorting = { ['Entregue'] = 'closed_date_desc' },
      work_item_type_display = {
        ['Epic'] = { text = '👑', color = 'WorkhorseTypeEpic' },
        ['Feature'] = { text = '🏆', color = 'WorkhorseTypeFeature' },
        ['User Story'] = { text = '📖', color = 'WorkhorseTypeUserStory' },
        ['Bug'] = { text = '🪲', color = 'WorkhorseTypeBug' },
        ['Task'] = { text = '✅', color = 'WorkhorseTypeTask' },
      },
      work_item_type_decorations = {
        ['User Story'] = { 'WorkhorseItalic' },
        ['Epic'] = { 'WorkhorseBold' },
      },
      tag_title_colors = {
        ['User Story'] = { ['Suporte'] = 'MiniIconsOrange', ['Projeto'] = 'MiniIconsGreen', ['Melhoria'] = 'MiniIconsBlue' },
      },
      confirm_changes = 'OnlyOnRemovals',
      cache = { enabled = true, ttl = 300 },
    },
  },

  -- SpotlightDimmer: dims every split but the focused one through the desktop
  -- overlay (a no-op outside tmux/ssh). The local checkout wins when present.
  -- Over ssh config/ssh_title.lua owns 'titlestring', hence manage_title = false.
  {
    'thomazmoura/spotlight-dimmer',
    dir = spotlight_local and spotlight_checkout or nil,
    lazy = false,
    config = function(plugin)
      vim.opt.rtp:append(plugin.dir .. '/' .. spotlight_subdir)
      require('spotlight-dimmer').setup({ manage_title = false })
    end,
  },
}
