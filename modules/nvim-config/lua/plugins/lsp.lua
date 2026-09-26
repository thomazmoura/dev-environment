local home = vim.env.HOME

-- Diagnostics: one line per diagnostic under the code (virtual_lines) or all
-- of them at the end of the line (virtual_text), toggled with <Leader>l
local function diagnostic_config(lines)
  vim.diagnostic.config({
    virtual_lines = lines,
    virtual_text = not lines,
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = '\u{ea87} ',
        [vim.diagnostic.severity.WARN] = '\u{f071} ',
        [vim.diagnostic.severity.HINT] = '\u{f1238} ',
        [vim.diagnostic.severity.INFO] = '\u{f449} ',
      },
    },
  })
end

-- Buffer-local keymaps for every buffer a language server attaches to. A
-- mapping the buffer already has (the JSON/Angular <Leader>f, the SQL
-- <Leader>r) wins over the LSP one.
local function on_attach(args)
  local buffer = args.buf
  local function map(mode, lhs, rhs, desc)
    for _, m in ipairs(type(mode) == 'table' and mode or { mode }) do
      if vim.fn.maparg(lhs, m, false, true).buffer ~= 1 then
        vim.keymap.set(m, lhs, rhs, { buffer = buffer, desc = desc })
      end
    end
  end

  map('n', 'gd', vim.lsp.buf.definition, 'Go to definition')
  map('n', 'gD', vim.lsp.buf.declaration, 'Go to declaration')
  map('n', 'gi', '<cmd>Telescope lsp_implementations<cr>', 'Implementations')
  map('n', 'gr', '<cmd>Telescope lsp_references<cr>', 'References')
  map('n', 'K', vim.lsp.buf.hover, 'Hover')
  map('n', 'gh', vim.lsp.buf.hover, 'Hover')
  map('n', '<Leader>K', vim.lsp.buf.signature_help, 'Signature help')
  map('i', '<C-k>', vim.lsp.buf.signature_help, 'Signature help')
  map('n', '<Leader>D', vim.lsp.buf.type_definition, 'Type definition')
  map('n', '<Leader>r', vim.lsp.buf.rename, 'Rename')
  map({ 'n', 'v' }, '<Leader>.', vim.lsp.buf.code_action, 'Code action')
  map('n', '<Leader>f', vim.lsp.buf.format, 'Format')
  map('n', '<Leader>t', '<cmd>Telescope lsp_dynamic_workspace_symbols<cr>', 'Workspace symbols')
end

return {
  {
    'neovim/nvim-lspconfig',
    lazy = false,
    keys = {
      { '<Leader>l', function()
        vim.g.diagnostic_lines = not vim.g.diagnostic_lines
        diagnostic_config(vim.g.diagnostic_lines)
      end, desc = 'Toggle diagnostic lines' },
      { '[d', function() vim.diagnostic.jump({ count = -1, float = true }) end, desc = 'Previous diagnostic' },
      { ']d', function() vim.diagnostic.jump({ count = 1, float = true }) end, desc = 'Next diagnostic' },
      { '[D', function() vim.diagnostic.jump({ count = -1, float = true, severity = vim.diagnostic.severity.ERROR }) end, desc = 'Previous error' },
      { ']D', function() vim.diagnostic.jump({ count = 1, float = true, severity = vim.diagnostic.severity.ERROR }) end, desc = 'Next error' },
      { '<Leader>gh', vim.diagnostic.open_float, desc = 'Line diagnostics' },
      { '<Leader>R', '<cmd>lsp restart<cr>', desc = 'Restart language servers' },
    },
    config = function()
      vim.g.diagnostic_lines = true
      diagnostic_config(true)

      -- NeoVim's gr* defaults would make gr (references) wait for a second key
      for _, lhs in ipairs({ 'grr', 'gra', 'grn', 'gri', 'grt', 'grx' }) do
        pcall(vim.keymap.del, { 'n', 'x' }, lhs)
      end

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('LspKeymaps', { clear = true }),
        callback = on_attach,
      })

      -- Server cmd/filetypes/root markers come from nvim-lspconfig's lsp/*.lua;
      -- completion capabilities are added to '*' by blink.cmp.

      vim.lsp.config('powershell_es', {
        bundle_path = home .. '/.language-servers/powershell',
      })

      vim.lsp.config('lua_ls', {
        cmd = { home .. '/.language-servers/lua/bin/lua-language-server' },
        settings = {
          Lua = {
            telemetry = { enable = false },
            completion = { callSnippet = 'Replace' },
            workspace = { checkThirdParty = false },
          },
        },
      })

      -- angularls claims every typescript and html buffer: only start it when
      -- there is an Angular workspace (not calling on_dir means "don't attach")
      vim.lsp.config('angularls', {
        root_dir = function(bufnr, on_dir)
          local root = vim.fs.root(bufnr, { 'angular.json', 'nx.json' })
          if root then on_dir(root) end
        end,
      })

      vim.lsp.config('yamlls', {
        settings = {
          yaml = {
            schemas = {
              ['https://json.schemastore.org/github-workflow.json'] = '/.github/workflows/*',
            },
          },
        },
      })

      local cucumber = {
        features = { '**/Features/*.feature' },
        glue = { '**/StepDefinitions/*.cs' },
        parameterTypes = {},
      }
      vim.lsp.config('cucumber_language_server', {
        settings = vim.tbl_extend('force', { cucumber = cucumber }, cucumber),
      })

      -- roslyn is enabled by roslyn.nvim itself
      vim.lsp.enable({
        'powershell_es', 'lua_ls', 'jsonls', 'ts_ls', 'angularls', 'yamlls',
        'vimls', 'emmet_ls', 'cssls', 'html', 'cucumber_language_server',
      })
    end,
  },

  -- C# through the Roslyn language server, which is the `roslyn-language-server`
  -- dotnet tool from modules/neovim-lsp/Setup-NeoVimLSP.ps1 (on PATH via
  -- ~/.dotnet/tools). `:Roslyn target` switches solutions.
  {
    'seblyng/roslyn.nvim',
    lazy = false,
    opts = {
      -- The server watches files; NeoVim doesn't do it a second time
      filewatching = 'roslyn',
      -- Solutions sit at the root of their own directory
      broad_search = false,
    },
    config = function(_, opts)
      require('roslyn').setup(opts)
      vim.lsp.config('roslyn', {
        settings = {
          -- Background analysis of open files only; analysing the whole
          -- solution pins a CPU core. gd/gr across the solution still work.
          ['csharp|background_analysis'] = {
            dotnet_analyzer_diagnostics_scope = 'openFiles',
            dotnet_compiler_diagnostics_scope = 'openFiles',
          },
          -- gd into code that only exists in NuGet dependencies
          ['csharp|symbol_search'] = {
            dotnet_search_reference_assemblies = true,
          },
          ['csharp|inlay_hints'] = {
            dotnet_enable_inlay_hints_for_parameters = true,
            csharp_enable_inlay_hints_for_implicit_variable_types = true,
            csharp_enable_inlay_hints_for_implicit_object_creation = true,
            csharp_enable_inlay_hints_for_lambda_parameter_types = true,
          },
          ['csharp|code_lens'] = {
            dotnet_enable_references_code_lens = true,
          },
        },
      })
    end,
  },

  -- NeoVim's API (and the plugins') for lua_ls, while editing this config
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
        'nvim-dap-ui',
      },
    },
  },

  {
    'hedyhli/outline.nvim',
    cmd = 'Outline',
    keys = { { '<Leader>o', '<cmd>Outline<cr>', desc = 'Symbols outline' } },
    opts = {},
  },

  {
    'folke/trouble.nvim',
    cmd = 'Trouble',
    keys = {
      { '<Leader>x', '<cmd>Trouble diagnostics toggle<cr>', desc = 'Diagnostics (Trouble)' },
      { '<Leader>X', '<cmd>Telescope diagnostics<cr>', desc = 'Diagnostics (Telescope)' },
    },
    opts = {},
  },
}
