--lualine settings
require('lualine').setup {
  options = {
    icons_enabled = false,
    theme = 'auto',
    component_separators = { left = '', right = ''},
    section_separators = { left = '', right = ''},
    disabled_filetypes = {},
    always_divide_middle = false,
    globalstatus = true,
  },
  sections = {
    lualine_a = {'mode'},
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
    lualine_x = {},
    lualine_y = {'progress', 'filetype', 'encoding'},
    lualine_z = {'location'}
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {'filename'},
    lualine_x = {'location'},
    lualine_y = {},
    lualine_z = {}
  },
  extensions = {}
}


