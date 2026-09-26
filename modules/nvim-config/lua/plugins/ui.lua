return {
  {
    'nvim-tree/nvim-web-devicons',
    lazy = true,
    config = function()
      local devicons = require('nvim-web-devicons')
      local function icon(glyph, color, name) return { icon = glyph, color = color, name = name } end
      devicons.setup({
        default = true,
        override = {
          vimrc = icon('', '#9ece6a', 'VimRC'),
          gvimrc = icon('', '#9ece6a', 'GVimRC'),
          vsvimrc = icon('', '#9ece6a', 'VSVimRC'),
          bashrc = icon('', '#FFFFFF', 'BashRC'),
          inputrc = icon('', '#FFFFFF', 'InputRC'),
          gitignore = icon('', '#8B2F1A', 'GitIgnore'),
          ps1 = icon('', '#7aa2f7', 'PowerShell'),
          cs = icon('', '#1a662e', 'CSharpFile'),
          csproj = icon('', '#7aa2f7', 'CSharpProject'),
          feature = icon('', '#22DD33', 'CucumberFeature'),
          ['module.ts'] = icon('', '#bb9af7', 'AngularModule'),
          ['component.ts'] = icon('', '#CD4277', 'AngularComponent'),
          ['service.ts'] = icon('', '#7aa2f7', 'AngularService'),
          ['spec.ts'] = icon('󰙨', '#9ece6a', 'AngularSpec'),
        },
      })
      devicons.set_default_icon('', '#6d8086')
    end,
  },

  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = {
      'MunifTanjim/nui.nvim',
      {
        'rcarriga/nvim-notify',
        opts = {
          render = 'wrapped-compact',
          max_width = 200,
          timeout = 10000,
          stages = 'fade_in_slide_out',
          top_down = false,
        },
      },
    },
    keys = {
      { '<Leader>n', '<cmd>Telescope noice<cr>', desc = 'Message history' },
    },
    opts = {
      lsp = {
        -- Markdown in hover/signature help rendered with tree-sitter
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
        },
      },
      routes = {
        -- "-- INSERT --" and "recording @q" as notifications
        { view = 'notify', filter = { event = 'msg_showmode' } },
        -- No "written" message on every save
        { filter = { event = 'msg_show', kind = '', find = 'written' }, opts = { skip = true } },
      },
      views = {
        notify = { replace = true },
      },
    },
  },

  {
    'nvim-lualine/lualine.nvim',
    event = 'VeryLazy',
    dependencies = { 'folke/noice.nvim' },
    opts = function()
      local noice = require('noice').api.status
      local function dadbod()
        if vim.fn.exists('*db_ui#statusline') == 0 then return '' end
        return vim.fn['db_ui#statusline']({ show = { 'db_name', 'table' }, separator = ' - ', prefix = '' })
      end
      local function workhorse()
        local ok, wh = pcall(require, 'workhorse')
        return ok and wh.lualine.get() or ''
      end
      local function encoding()
        return string.format('%s %s', vim.bo.fileencoding, vim.bo.bomb and 'BOM' or '')
      end

      return {
        options = {
          icons_enabled = false,
          theme = 'auto',
          component_separators = { left = '', right = '' },
          section_separators = { left = '', right = '' },
          always_divide_middle = false,
          globalstatus = true,
        },
        sections = {
          lualine_a = { 'mode' },
          lualine_b = { 'diagnostics', { 'filename', path = 1 } },
          lualine_c = { workhorse },
          lualine_x = {
            { noice.mode.get, cond = noice.mode.has, color = { fg = '#ff9e64' } },
            { noice.search.get, cond = noice.search.has, color = { fg = '#ff9e64' } },
          },
          lualine_y = { 'selectioncount', dadbod, 'progress', 'filetype', encoding, 'fileformat' },
          lualine_z = { 'location' },
        },
        inactive_sections = {
          lualine_c = { 'filename' },
          lualine_x = { 'location' },
        },
      }
    end,
  },

  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {},
  },

  {
    'karb94/neoscroll.nvim',
    event = 'VeryLazy',
    opts = {
      hide_cursor = false,
      easing = 'quadratic',
      duration_multiplier = 0.5,
    },
  },

  -- Rainbow brackets (tree-sitter based), but not on HTML
  {
    'HiPhish/rainbow-delimiters.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    main = 'rainbow-delimiters.setup',
    opts = { blacklist = { 'html' } },
  },

  -- Markdown rendered in normal mode. Not lazy-loaded, as markview asks.
  {
    'OXY2DEV/markview.nvim',
    lazy = false,
    opts = {
      buf_ignore = {},
      max_length = 99999,
      markdown = {
        list_items = { shift_width = 2 },
      },
    },
  },
}
