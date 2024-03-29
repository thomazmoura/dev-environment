-- cmp settings
-- Set up nvim-cmp.
-- Add additional capabilities supported by nvim-cmp
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

local lspconfig = require('lspconfig')

-- luasnip setup
local luasnip = require 'luasnip'

-- lsp_lines
Virtual_text = false
local function toggle_lsp_lines()
  require("lsp_lines").toggle()
  Virtual_text = not Virtual_text
  vim.diagnostic.config({
    virtual_text = Virtual_text,
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
end

-- Mappings.
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
local opts = { noremap = true, silent = true }
vim.keymap.set('n', '<Leader>E', '<cmd>Telescope diagnostics<cr>', opts)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist, opts)

-- LSP Mappings.
-- See `:help vim.lsp.*` for documentation on any of the below functions
local bufopts = { noremap = true, silent = true }
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
vim.keymap.set('n', 'gd', '<cmd>Telescope lsp_definitions<cr>', bufopts)
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
vim.keymap.set('n', '<Leader>.', vim.lsp.buf.code_action, bufopts)
vim.keymap.set('n', 'gr', '<cmd>Telescope lsp_references<cr>', bufopts)
vim.keymap.set('n', '<Leader>f', vim.lsp.buf.format, bufopts)
vim.keymap.set('n', '<Leader>t', '<cmd>Telescope lsp_dynamic_workspace_symbols<cr>', bufopts)
vim.keymap.set('n', '<Leader>a', '<cmd>Telescope diagnostics<cr>', bufopts)
vim.keymap.set('n', '<Leader>o', '<cmd>SymbolsOutline<cr>', bufopts)
vim.keymap.set('i', '<C-k>', vim.lsp.buf.signature_help, bufopts)

local lsp_flags = {
  -- This is the default in Nvim 0.7+
  debounce_text_changes = 150,
}


-- omnisharp settings
lspconfig.omnisharp.setup {
  capabilities = capabilities,
  flags = lsp_flags,
  cmd = {
    "dotnet", "/home/developer/.language-servers/omnisharp/OmniSharp.dll", "--languageserver", "--hostPID",
    tostring(vim.fn.getpid())
  },
}

-- powershell settings
lspconfig.powershell_es.setup {
  capabilities = capabilities,
  flags = lsp_flags,
  bundle_path = '/home/developer/.language-servers/powershell',
}

-- lua LS settings
lspconfig.lua_ls.setup {
  capabilities = capabilities,
  flags = lsp_flags,
  cmd = { "/home/developer/.language-servers/lua/bin/lua-language-server" },
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
    },
  },
}

-- json LS settings
lspconfig.jsonls.setup {
  capabilities = capabilities,
  flags = lsp_flags,
}

-- TypeScript LS settings
lspconfig.tsserver.setup {
  capabilities = capabilities,
  flags = lsp_flags,
}

-- Angular LS settings
lspconfig.angularls.setup {
  capabilities = capabilities,
  flags = lsp_flags,
}

-- YAML LS settings
require('lspconfig').yamlls.setup {
  capabilities = capabilities,
  flags = lsp_flags,
  settings = {
    yaml = {
      schemas = {
            ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
      },
    },
  }
}

-- VIM LS settings
lspconfig.vimls.setup {
  capabilities = capabilities,
  flags = lsp_flags,
}

-- Markdown LS Settings (Marksman)
lspconfig.marksman.setup {
  capabilities = capabilities,
  flags = lsp_flags,
}

-- Emmet LS
lspconfig.emmet_ls.setup{
  capabilities = capabilities,
  flags = lsp_flags,
}

-- CSS LS
lspconfig.cssls.setup {
  capabilities = capabilities,
  flags = lsp_flags,
}

-- Proper icons
local signs = { Error = " ", Warn = " ", Hint = " ", Info = " " }
for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
end

-- LuaSnip settings
require("luasnip.loaders.from_vscode").lazy_load()
require("luasnip.loaders.from_vscode").lazy_load({ paths = { "~/.local/share/nvim/site/vscode-snippets" } })

-- Symbols outline
require("symbols-outline").setup()

