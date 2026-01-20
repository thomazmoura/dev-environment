require("workhorse").setup({
  -- Required: Azure DevOps project name
  project = "GTI",

  -- Optional: Override environment variables
  server_url = nil,  -- Falls back to AZURE_DEVOPS_URL
  pat = nil,         -- Falls back to AZURE_DEVOPS_PAT

  -- Team and board column configuration
  team = "Equipe ArquiteturaNET",
  grouping_mode = "board_column",
  default_board = "Stories",

  -- Work item defaults
  default_work_item_type = "User Story",
  default_area_path = nil,       -- Uses project root if nil
  default_iteration_path = nil,  -- Uses project root if nil

  -- State for soft delete
  deleted_state = "Removed",

  -- Available states per work item type (customize as needed)
  available_states = {
    ["Epic"] = { "New", "Active", "Resolved", "Closed", "Removed" },
    ["Feature"] = { "New", "Active", "Resolved", "Closed", "Removed" },
    ["User Story"] = { "New", "Active", "Resolved", "Closed", "Removed" },
    ["Bug"] = { "New", "Active", "Resolved", "Closed" },
    ["Task"] = { "New", "Active", "Closed" },
  },

  -- State header colors (highlight group names)
  state_colors = {
    ["New"] = "Special",
    ["Active"] = "Function",
    ["Resolved"] = "Identifier",
    ["Closed"] = "LspCodeLens",
    ["Removed"] = "Debug",
  },

  -- Board column colors (highlight group names)
  column_colors = {
    ["Em Andamento"] = "Function",
    ["A Ser Feito"] = "DiagnosticHint",
    ["Backlog"] = "Special",
    ["Bloqueado"] = "ErrorMsg",
    ["Feito"] = "Identifier",
    ["Homologação"] = "Debug",
    ["Entregue"] = "LspCodeLens",
    ["New"] = "Special",
  },

  -- Board column ordering
  column_order = {
    "Em Andamento",
    "Bloqueado",
    "A Ser Feito",
    "Homologação",
    "Feito",
    "Backlog",
    "New",
    "Entregue",
  },

  -- Work item type display (text and color independently configurable)
  work_item_type_display = {
    ["Epic"] = { text = "🏆", color = "WorkhorseTypeEpic" },
    ["Feature"] = { text = "🏅", color = "WorkhorseTypeFeature" },
    ["User Story"] = { text = "📋", color = "WorkhorseTypeUserStory" },
    ["Bug"] = { text = "🪲", color = "WorkhorseTypeBug" },
    ["Task"] = { text = "✅", color = "WorkhorseTypeTask" },
  },

  work_item_type_decorations = {
    ["User Story"] = { "WorkhorseItalic" },
    ["Epic"] = { "WorkhorseBold" }
  },

  tag_title_colors = { ["User Story"] = { ["Suporte"] = "MiniIconsOrange", ["Projeto"] = "MiniIconsGreen", ["Melhoria"] = "MiniIconsBlue",}},

  -- UI options
  confirm_changes = "OnlyOnRemovals",  -- Show confirmation dialog before saving
  default_area_path = "GTI\\ArquiteturaNET",

  -- Cache settings
  cache = {
    enabled = true,
    ttl = 300,  -- 5 minutes
  },
})

vim.keymap.set('n', '<leader>wt', '<cmd>Workhorse query a7977848-adab-4453-a4cf-39c28163ac3c<cr>', default_global_options) --Tree
vim.keymap.set('n', '<leader>wu', '<cmd>Workhorse query 729b31ef-3bce-4fcb-b300-0342e4ce69c8<cr>', default_global_options) --User Stories
vim.keymap.set('n', '<leader>wf', '<cmd>Workhorse query 38cfedab-c989-41bb-9d28-71d2c4ad9464<cr>', default_global_options) --Feature
vim.keymap.set('n', '<leader>we', '<cmd>Workhorse query 7c0761cd-ba78-4769-a28e-68685934d0aa<cr>', default_global_options) --Epic
vim.keymap.set('n', '<leader>wl', '<cmd>Workhorse query d53e77f7-d7c8-49ff-ba14-35a061d047e9<cr>', default_global_options) --LuaLine
vim.keymap.set('n', '<leader>wa', '<cmd>Workhorse query 3c82101c-2a67-408f-9fd7-8ad00a55710c<cr>', default_global_options) --Full (All)
vim.keymap.set('n', '<leader>wx', '<cmd>Workhorse query 9a90e30d-0827-4fe9-9426-e70a8fd62ca6<cr>', default_global_options) --Trash
