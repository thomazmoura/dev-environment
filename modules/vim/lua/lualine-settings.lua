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
    lualine_c = {},
    lualine_x = {
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
    },
    lualine_y = {
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
