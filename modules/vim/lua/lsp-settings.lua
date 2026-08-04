-- Util
local home_directory = vim.fn.expand("$HOME");

-- NeoDev settings
require("neodev").setup({
  library = { plugins = { "nvim-dap-ui" }, types = true }
})

-- cmp settings
-- Set up nvim-cmp.
-- Add additional capabilities supported by nvim-cmp
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

-- luasnip setup
local luasnip = require 'luasnip'

-- lsp_lines
Virtual_text = false
local function toggle_lsp_lines()
  require("lsp_lines").toggle()
  Virtual_text = not Virtual_text
  vim.diagnostic.config({
    virtual_text = not Virtual_text,
  })
end
vim.diagnostic.config({
  virtual_text = Virtual_text,
})
require('lsp_lines').setup()
vim.keymap.set(
  "n",
  "<Leader>l",
  toggle_lsp_lines,
  { desc = "Toggle lsp_lines" }
)
toggle_lsp_lines()

-- nvim-cmp setup
local cmp = require 'cmp'
if cmp ~= nil then
  cmp.setup {
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
    mapping = cmp.mapping.preset.insert({
          ['<C-d>'] = cmp.mapping.scroll_docs(-4),
          ['<C-u>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm {
        behavior = cmp.ConfirmBehavior.Replace,
        select = true,
      },
          ['<Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        else
          fallback()
        end
      end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, { 'i', 's' }),
    }),
    sources = {
      { name = 'nvim_lsp' },
      { name = 'luasnip' },
      { name = 'buffer' },
      { name = 'path' },
    },
  }

  -- Set configuration for specific filetype.
  cmp.setup.filetype('gitcommit', {
    sources = cmp.config.sources({
      { name = 'cmp_git' }, -- You can specify the `cmp_git` source if you were installed it.
    }, {
      { name = 'buffer' },
    })
  })

  -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
  for _, v in pairs({ '/', '?' }) do
    cmp.setup.cmdline(v, {
      mapping = cmp.mapping.preset.cmdline(),
      sources = {
        { name = 'buffer' }
      }
    })
  end

  -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline(':', {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
      { name = 'path' }
    }, {
      { name = 'cmdline' }
    })
  })

  cmp.setup.filetype('sql', {
    sources = {
      { name = 'luasnip' },
      { name = 'vim-dadbod-completion' },
      { name = 'buffer' }
    }
  })
end

-- Mappings.
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
local opts = { noremap = true, silent = true }
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
vim.keymap.set('n', '[D', function() vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.ERROR }) end, opts)
vim.keymap.set('n', ']D', function() vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR }) end, opts)
vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist, opts)

-- LSP Mappings.
-- See `:help vim.lsp.*` for documentation on any of the below functions
local bufopts = { noremap = true, silent = true }
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
vim.keymap.set('n', 'gh', vim.lsp.buf.hover, bufopts)
vim.keymap.set('n', '<Leader>gh', vim.diagnostic.open_float, bufopts)
vim.keymap.set('n', 'gi', '<cmd>Telescope lsp_implementations<cr>', bufopts)
vim.keymap.set('n', '<Leader>K', vim.lsp.buf.signature_help, bufopts)
vim.keymap.set('n', '<Leader>wa', vim.lsp.buf.add_workspace_folder, bufopts)
vim.keymap.set('n', '<Leader>wr', vim.lsp.buf.remove_workspace_folder, bufopts)
vim.keymap.set('n', '<Leader>wl', function()
  print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
end, bufopts)
vim.keymap.set('n', '<Leader>D', vim.lsp.buf.type_definition, bufopts)
vim.keymap.set('n', '<Leader>r', vim.lsp.buf.rename, bufopts)
vim.keymap.set('n', '<Leader>R', '<cmd>LspRestart<cr>')
vim.keymap.set({ 'v', 'n' }, '<Leader>.', vim.lsp.buf.code_action, bufopts)
vim.keymap.set('n', 'gr', '<cmd>Telescope lsp_references<cr>', bufopts)
vim.keymap.set('n', '<Leader>f', vim.lsp.buf.format, bufopts)
vim.keymap.set('n', '<Leader>t', '<cmd>Telescope lsp_dynamic_workspace_symbols<cr>', bufopts)
vim.keymap.set('n', '<Leader>x', '<cmd>Trouble diagnostics toggle<cr>', bufopts)
vim.keymap.set('n', '<Leader>X', '<cmd>Telescope diagnostics<cr>', bufopts)
vim.keymap.set('n', '<Leader>o', '<cmd>SymbolsOutline<cr>', bufopts)
vim.keymap.set('i', '<C-k>', vim.lsp.buf.signature_help, bufopts)

-- Defaults shared by every server. The '*' entry is merged into each named
-- config by vim.lsp.config, so capabilities and flags no longer need repeating
-- once per server the way the old lspconfig.<server>.setup{} calls did.
--
-- Server cmd/filetypes/root_markers come from nvim-lspconfig's lsp/<name>.lua
-- definitions, which are picked up from runtimepath automatically.
vim.lsp.config('*', {
  capabilities = capabilities,
  flags = {
    -- This is the default in Nvim 0.7+
    debounce_text_changes = 150,
  },
})


-- C# settings (Roslyn language server, via seblyng/roslyn.nvim)
--
-- Replaces OmniSharp, which was archived upstream. The server binary comes from
-- the `roslyn-language-server` global dotnet tool installed by
-- modules/neovim-lsp/Setup-NeoVimLSP.ps1, and is found on PATH via ~/.dotnet/tools.
--
-- roslyn.nvim resolves the .sln/.csproj target on its own, so the old
-- omnisharp-solution.lua picker (and its `**/*.sln` glob, which walked every
-- node_modules on startup) is gone. Use `:Roslyn target` to switch solutions.
require('roslyn').setup {
  -- Let the server own file watching instead of running Neovim's watcher over
  -- the same tree as well.
  filewatching = 'roslyn',

  -- Solutions here sit at the root of their own directory, so the plain upward
  -- search suffices; broad_search would walk sibling trees on every attach.
  broad_search = false,
}

vim.lsp.config('roslyn', {
  settings = {
    -- Keep background passes scoped to open files. Analysing the whole solution
    -- is what pinned a CPU core under OmniSharp. Cross-solution `gd`/`gr` still
    -- work, since those are on-demand queries rather than background analysis.
    ['csharp|background_analysis'] = {
      dotnet_analyzer_diagnostics_scope = 'openFiles',
      dotnet_compiler_diagnostics_scope = 'openFiles',
    },

    -- Replaces OmniSharp's enableDecompilationSupport: lets `gd` descend into
    -- code that only exists in NuGet dependencies.
    ['csharp|symbol_search'] = {
      dotnet_search_reference_assemblies = true,
    },

    -- OmniSharp had every inlay hint category switched on; these are the ones
    -- that earn their cost.
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

-- powershell settings
vim.lsp.config('powershell_es', {
  bundle_path = home_directory .. '/.language-servers/powershell',
})

-- lua LS settings
vim.lsp.config('lua_ls', {
  cmd = { home_directory .. "/.language-servers/lua/bin/lua-language-server" },
  settings = {
    Lua = {
      runtime = {
        -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
        version = 'LuaJIT',
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = { 'vim' },
      },
      workspace = {
        -- Make the server aware of Neovim runtime files
        library = vim.api.nvim_get_runtime_file("", true),
        -- Disable annoying constant notification
        checkThirdParty = false,
      },
      -- Do not send telemetry data containing a randomized but unique identifier
      telemetry = {
        enable = false,
      },
      completion = {
        callSnippet = "Replace"
      }
    },
  },
})

-- Create an augroup named JsonToJsonc (so that comments won't be an issue anymore with JSON)
local json_to_jsonc_group = vim.api.nvim_create_augroup("JsonToJsonc", { clear = true })

-- Create an autocmd in the JsonToJsonc group that sets the filetype to jsonc for json files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "json",
  callback = function()
    vim.bo.filetype = "jsonc"
  end,
  group = json_to_jsonc_group,
})

-- Angular LS settings
--
-- angularls claims every typescript and html buffer, so without this it starts
-- an ngserver in plain TypeScript projects too. Under the old lspconfig
-- framework a root_dir that found nothing meant "do not attach"; vim.lsp.enable
-- only uses root_markers to *compute* a root, and still attaches when none
-- match. Declining to call on_dir is what suppresses the attach now.
vim.lsp.config('angularls', {
  root_dir = function(bufnr, on_dir)
    local root = vim.fs.root(bufnr, { 'angular.json', 'nx.json' })
    if root then
      on_dir(root)
    end
  end,
})

-- YAML LS settings
vim.lsp.config('yamlls', {
  settings = {
    yaml = {
      schemas = {
            ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
      },
    },
  }
})

-- Cucumber
vim.lsp.config('cucumber_language_server', {
  settings = {
    cucumber = {
      features = { "**/Features/*.feature" },
      glue = { "**/StepDefinitions/*.cs" },
      parameterTypes = {},
    },
    features = { "**/Features/*.feature" },
    glue = { "**/StepDefinitions/*.cs" },
    parameterTypes = {},
  },
})

-- Servers that need nothing beyond the nvim-lspconfig defaults plus the '*'
-- entry above: jsonls, ts_ls, vimls, emmet_ls, cssls, html.
--
-- roslyn is absent on purpose: roslyn.nvim's own plugin/roslyn.lua already
-- calls vim.lsp.enable('roslyn').
vim.lsp.enable {
  'powershell_es',
  'lua_ls',
  'jsonls',
  'ts_ls',
  'angularls',
  'yamlls',
  'vimls',
  'emmet_ls',
  'cssls',
  'html',
  'cucumber_language_server',
}

-- Proper icons
local signs = { Error = " ", Warn = " ", Hint = "󱈸 ", Info = " " }
for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
end

-- LuaSnip settings
require("luasnip.loaders.from_vscode").lazy_load()
require("luasnip.loaders.from_vscode").lazy_load({
  paths = { home_directory .. "/.local/share/nvim/site/vscode-snippets" }
})

-- Symbols outline
require("symbols-outline").setup()

-- Trouble.nvim
require("trouble").setup()
