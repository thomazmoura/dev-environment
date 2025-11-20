local function dadbod_status()
  return vim.api.nvim_call_function('db_ui#statusline', {
    {
      show = {
       'db_name',
       'table'
      },
      separator = ' - ',
      prefix = ''
    }
  })
end

local sidekick_status_component
local sidekick_cli_component
do
  local ok, sidekick_status = pcall(require, "sidekick.status")
  if ok then
    sidekick_status_component = {
      function()
        return " "
      end,
      color = function()
        local info = sidekick_status.get()
        if not info then
          return
        end
        if info.kind == "Error" then
          return "DiagnosticError"
        end
        if info.busy then
          return "DiagnosticWarn"
        end
        return "Special"
      end,
      cond = function()
        return sidekick_status.get() ~= nil
      end,
    }

    sidekick_cli_component = {
      function()
        local sessions = sidekick_status.cli()
        return " " .. (#sessions > 1 and #sessions or "")
      end,
      cond = function()
        return #sidekick_status.cli() > 0
      end,
      color = function()
        return "Special"
      end,
    }
  end
end

local lualine_x_components = {
  {
    require("noice").api.status.mode.get,
    cond = require("noice").api.status.mode.has,
    color = { fg = "#ff9e64" },
  },
  {
    require("noice").api.status.search.get,
    cond = require("noice").api.status.search.has,
    color = { fg = "#ff9e64" },
  },
}

if sidekick_cli_component then
  table.insert(lualine_x_components, sidekick_cli_component)
end

--lualine settings
require('lualine').setup {
  options = {
    icons_enabled = false,
    theme = 'auto',
    component_separators = { left = '', right = '' },
    section_separators = { left = '', right = '' },
    disabled_filetypes = {},
    always_divide_middle = false,
    globalstatus = true,
  },
  sections = {
    lualine_a = { 'mode' },
    lualine_b = {
      {
        'diagnostics'
      },
      {
        'filename',
        path = 1,
      }
    },
    lualine_c = sidekick_status_component and { sidekick_status_component } or {},
    lualine_x = lualine_x_components,
    lualine_y = {
      'selectioncount',
      dadbod_status,
      'progress',
      'filetype',
      function()
        local encoding = vim.bo.fileencoding
        local bom = vim.bo.bomb and 'BOM' or ''
        return string.format('%s %s', encoding, bom)
      end,
      'fileformat'
    },
    lualine_z = { 'location' }
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = { 'filename' },
    lualine_x = { 'location' },
    lualine_y = {},
    lualine_z = {}
  },
  extensions = {}
}
