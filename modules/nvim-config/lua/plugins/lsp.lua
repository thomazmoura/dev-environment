local home = vim.env.HOME

-- The node-based servers: their own prefix and node, from
-- modules/neovim-lsp/Install-LanguageServerNodePackages.ps1. Started through
-- that node, not the one on PATH, so a project pinned to an old node (its
-- .node-version) still gets them -- they only read its node_modules.
local node_lsp = home .. '/.language-servers/node'
local node = node_lsp .. '/node'
local function node_server(bin, ...)
  return { node, node_lsp .. '/node_modules/.bin/' .. bin, ... }
end

-- The @angular/core version in the project's package.json, as nvim-lspconfig's
-- angularls does: ngserver adapts to older projects with it. Matched as text,
-- since older package.json files are not always strict JSON.
local function angular_core_version(root)
  local ok, lines = pcall(vim.fn.readfile, root .. '/package.json')
  if not ok then return '' end
  local version = table.concat(lines, '\n'):match('"@angular/core"%s*:%s*"[^"%d]*(%d+%.%d+%.%d+)')
  return version or ''
end

local function angular_major(root)
  return tonumber(angular_core_version(root):match('^%d+'))
end

-- Angular 11 to 14: the ngserver of the project's own major, on the node it
-- supports, from modules/neovim-lsp/Install-AngularLanguageServer.ps1. It is
-- installed in the background the first time such a project opens; the
-- buffers opened meanwhile start the server when it is done.
local legacy_angular = home .. '/.language-servers/angular/'
local legacy_installs = {} -- major -> the starts waiting for its install
local legacy_failed = {}
local function with_legacy_angular(major, start)
  local marker = legacy_angular .. major .. '/.installed'
  if vim.uv.fs_stat(marker) then return start() end
  if legacy_failed[major] then return end
  if legacy_installs[major] then
    table.insert(legacy_installs[major], start)
    return
  end
  legacy_installs[major] = { start }
  vim.notify('Installing the Angular ' .. major .. ' language server...', vim.log.levels.INFO)
  vim.system({
    'pwsh', '-NoProfile', '-File',
    home .. '/.modules/neovim-lsp/Install-AngularLanguageServer.ps1', '-Major', tostring(major),
  }, { text = true }, vim.schedule_wrap(function(result)
    local starts = legacy_installs[major]
    legacy_installs[major] = nil
    if result.code ~= 0 or not vim.uv.fs_stat(marker) then
      legacy_failed[major] = true
      local output = vim.trim((result.stderr or '') .. '\n' .. (result.stdout or ''))
      vim.notify('Angular ' .. major .. ' language server install failed:\n'
        .. output:sub(-1500), vim.log.levels.ERROR)
      return
    end
    vim.notify('Angular ' .. major .. ' language server installed', vim.log.levels.INFO)
    for _, waiting in ipairs(starts) do waiting() end
  end))
end

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

      for name, cmd in pairs({
        jsonls = node_server('vscode-json-language-server', '--stdio'),
        cssls = node_server('vscode-css-language-server', '--stdio'),
        html = node_server('vscode-html-language-server', '--stdio'),
        ts_ls = node_server('typescript-language-server', '--stdio'),
        yamlls = node_server('yaml-language-server', '--stdio'),
        vimls = node_server('vim-language-server', '--stdio'),
        emmet_ls = node_server('emmet-ls', '--stdio'),
        cucumber_language_server = node_server('cucumber-language-server', '--stdio'),
      }) do
        vim.lsp.config(name, { cmd = cmd })
      end

      -- angularls claims every typescript and html buffer: only start it when
      -- there is an Angular workspace (not calling on_dir means "don't attach").
      -- The current ngserver fills templates before Angular 15 with false
      -- errors: 11 to 14 get the release of their own major, older projects
      -- make do with ts_ls.
      local warned_node_modules = {}
      vim.lsp.config('angularls', {
        root_dir = function(bufnr, on_dir)
          local root = vim.fs.root(bufnr, { 'angular.json', 'nx.json' })
          if not root then return end
          local major = angular_major(root)
          if major and major < 11 then return end
          if not vim.uv.fs_stat(root .. '/node_modules') and not warned_node_modules[root] then
            warned_node_modules[root] = true
            vim.notify('No node_modules in ' .. root .. ': Angular LSP is limited until '
              .. '`npm install` runs there with the project\'s node (the Frontend pane, prefix+a)',
              vim.log.levels.WARN)
          end
          if major and major < 15 then
            with_legacy_angular(major, function()
              if vim.api.nvim_buf_is_valid(bufnr) then on_dir(root) end
            end)
          else
            on_dir(root)
          end
        end,
        -- ngserver needs TypeScript >= 5.0: the project's when it is new
        -- enough, else the servers' own. @angular/language-service, though,
        -- must be the one ngserver was released with -- a project's older
        -- copy lacks the API it calls. The same goes for the older majors,
        -- whose ngserver wants the project's TypeScript 4 (or its prefix's).
        cmd = function(dispatchers, config)
          local root = config.root_dir
          local major = angular_major(root)
          if major and major < 15 then
            local prefix = legacy_angular .. major
            local servers = prefix .. '/node_modules'
            local ngserver = servers .. '/@angular/language-server'
            return vim.lsp.rpc.start({
              prefix .. '/node', ngserver .. '/bin/ngserver', '--stdio',
              '--tsProbeLocations', table.concat({ root .. '/node_modules', servers }, ','),
              '--ngProbeLocations', table.concat({ ngserver .. '/node_modules', servers }, ','),
            }, dispatchers)
          end
          local servers = node_lsp .. '/node_modules'
          local ngserver = servers .. '/@angular/language-server'
          return vim.lsp.rpc.start({
            node, ngserver .. '/bin/ngserver', '--stdio',
            '--tsProbeLocations', table.concat({ root .. '/node_modules', servers }, ','),
            '--ngProbeLocations', table.concat({ ngserver .. '/node_modules', servers }, ','),
            '--angularCoreVersion', angular_core_version(root),
          }, dispatchers)
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

      -- SQL: the servers claim the sql filetype, so they are not in
      -- vim.lsp.enable: config/sql_dialect.lua starts the ones matching each
      -- buffer's dadbod connection or syntax. SqlToolsService and the Postgres
      -- server need no database for syntax errors and formatting.
      local function sql_root(bufnr, on_dir)
        on_dir(vim.fs.root(bufnr, { 'postgres-language-server.jsonc', '.git' }) or vim.fn.getcwd())
      end
      -- sql buffers complete from dadbod and sqlserver_assist only (blink's sql_assist source)
      local function no_completion(client) client.server_capabilities.completionProvider = nil end

      -- Postgres: a project's own postgres-language-server.jsonc, or else
      -- these settings (it doesn't format without either). They are layered
      -- over the file, so a project's are left alone. Not --config-path: the
      -- server is a daemon shared by every NeoVim, started with the first one's.
      vim.lsp.config('postgres_lsp', {
        cmd = { home .. '/.language-servers/postgres/postgres-language-server', 'lsp-proxy' },
        root_dir = sql_root,
        on_init = function(client)
          no_completion(client)
          if vim.uv.fs_stat(client.root_dir .. '/postgres-language-server.jsonc') then return end
          client.settings = {
            -- As the SQL Server formatter does; x::int stays x::int, not CAST(x AS int)
            format = { enabled = true, keywordCase = 'upper', castStyle = 'operator' },
            db = { disableConnection = true },
          }
          client:notify('workspace/didChangeConfiguration', { settings = client.settings })
        end,
      })

      -- SQL Server: SqlToolsService, the server behind VS Code's mssql
      -- extension. Formatter options: format.options in its
      -- SqlFormatterOptions.cs (mssql.nvim documents the older ones)
      vim.lsp.config('sqlserver_ls', {
        cmd = { home .. '/.language-servers/sqlserver/MicrosoftSqlToolsServiceLayer' },
        filetypes = { 'sql' },
        root_dir = sql_root,
        on_init = no_completion,
        settings = {
          mssql = {
            format = {
              options = {
                builtInFunctionCasing = 'Uppercase',
                -- Else a GO ending the file is dropped
                persistTrailingGo = true,
              },
            },
          },
        },
      })

      -- SQL Server: our own server (modules/sql-assist), for what SqlToolsService
      -- lacks: "Expand *" in the code actions (<Leader>.), join conditions and
      -- INSERT column lists in the completion, the statements of <Leader>r.
      -- Without the .NET diagnostics server, which would let other processes
      -- read the passwords it holds (see its Hardening.cs)
      vim.lsp.config('sqlserver_assist', {
        cmd = { home .. '/.language-servers/sqlserver-assist/SqlServerAssist' },
        cmd_env = { DOTNET_EnableDiagnostics = '0' },
        filetypes = { 'sql' },
        root_dir = sql_root,
      })
      require('config.sql_dialect').setup()

      -- roslyn is enabled by roslyn.nvim itself
      vim.lsp.enable({
        'powershell_es', 'lua_ls', 'jsonls', 'ts_ls', 'angularls', 'yamlls',
        'vimls', 'emmet_ls', 'cssls', 'html', 'cucumber_language_server',
      })
    end,
  },

  -- C# through the Roslyn language server, which is the `roslyn-language-server`
  -- dotnet tool from modules/neovim-lsp/Setup-NeoVimLSP.ps1 (on PATH via
  -- ~/.dotnet/tools). `:Roslyn target` switches solutions. A project its
  -- solution doesn't list is opened alongside the solution.
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

      -- Roslyn loads only the projects a solution lists, not the ones they
      -- reference: a file of an unlisted project ends up in a misc project
      -- where gd/gi/hover find nothing outside the file.
      local discovery = require('roslyn.sln.discovery')
      local sln_api = require('roslyn.sln.api')
      local store = require('roslyn.store')

      -- Its solutions upward when none of them lists the buffer's project
      local function unlisted(bufnr)
        local csproj = discovery.find_project(bufnr)
        if not csproj then return end
        local solutions = discovery.find_solutions_for_buffer(bufnr)
        for _, solution in ipairs(solutions) do
          if sln_api.exists_in_target(solution, csproj) then return end
        end
        return csproj, solutions
      end

      -- Opened first, such a file would get a server for its project alone,
      -- which sees the rest of the solution as compiled DLLs: point
      -- roslyn.nvim at the nearest solution instead
      local resolve = vim.lsp.config.roslyn.root_dir
      local function root_dir(bufnr, on_dir)
        local _, solutions = unlisted(bufnr)
        if solutions and #solutions > 0
          and not vim.list_contains(solutions, store.get_selected_target()) then
          store.set_selected_target(solutions[1])
        end
        return resolve(bufnr, on_dir)
      end

      -- ...and the server for that solution opens the project too
      local opened = {} -- client id -> csproj -> true
      local function on_attach(client, bufnr)
        local solution = store.get(client.id)
        local csproj = solution and unlisted(bufnr)
        if not csproj or sln_api.exists_in_target(solution, csproj) then return end
        opened[client.id] = opened[client.id] or {}
        if opened[client.id][csproj] then return end
        opened[client.id][csproj] = true
        client:notify('project/open', { projects = { vim.uri_from_fname(csproj) } })
      end

      vim.lsp.config('roslyn', {
        root_dir = root_dir,
        on_attach = on_attach,
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
