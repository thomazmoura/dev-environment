local M = {}

-- Store the currently selected solution
M.selected_solution = nil

-- Get project root directory using lspconfig patterns
function M.get_root_dir()
  local lspconfig = require('lspconfig')
  local root_pattern = lspconfig.util.root_pattern('*.sln', '.git')
  local cwd = vim.fn.getcwd()
  return root_pattern(cwd) or cwd
end

-- Find all .sln files in the project root
function M.find_solutions(root)
  local cwd = vim.fn.getcwd()
  vim.fn.chdir(root)
  local solutions = vim.fn.glob('**/*.sln', false, true)
  vim.fn.chdir(cwd)

  -- Convert to absolute paths
  local absolute_solutions = {}
  for _, solution in ipairs(solutions) do
    table.insert(absolute_solutions, root .. '/' .. solution)
  end

  return absolute_solutions
end

-- Read cached solution selection
function M.read_cache(root)
  local cache_file = root .. '/.vim/omnisharp-selection'
  local stat = vim.loop.fs_stat(cache_file)

  if not stat then
    return nil
  end

  local file = io.open(cache_file, 'r')
  if not file then
    return nil
  end

  local solution = file:read('*line')
  file:close()

  -- Verify the solution file still exists
  if solution and vim.loop.fs_stat(solution) then
    return solution
  end

  return nil
end

-- Write solution selection to cache
function M.write_cache(root, solution_path)
  local vim_dir = root .. '/.vim'
  local cache_file = vim_dir .. '/omnisharp-selection'

  -- Create .vim directory if it doesn't exist
  vim.fn.mkdir(vim_dir, 'p')

  local file = io.open(cache_file, 'w')
  if not file then
    vim.notify('Failed to write OmniSharp selection cache', vim.log.levels.ERROR)
    return false
  end

  file:write(solution_path)
  file:close()

  return true
end

-- Build OmniSharp command with optional solution flag
function M.build_omnisharp_cmd(solution)
  local cmd = { 'omnisharp' }

  if solution then
    table.insert(cmd, '-s')
    table.insert(cmd, solution)
  end

  return cmd
end

-- Get solution to use on startup
function M.get_startup_solution()
  local root = M.get_root_dir()
  local solutions = M.find_solutions(root)

  -- No solutions found
  if #solutions == 0 then
    return nil
  end

  -- Single solution - auto-select
  if #solutions == 1 then
    return solutions[1]
  end

  -- Multiple solutions - check cache
  local cached = M.read_cache(root)
  if cached then
    return cached
  end

  -- Multiple solutions, no valid cache
  return nil
end

-- Show Telescope picker and select solution
function M.select_solution()
  local root = M.get_root_dir()
  local solutions = M.find_solutions(root)

  if #solutions == 0 then
    vim.notify('No solution files found in project', vim.log.levels.WARN)
    return
  end

  if #solutions == 1 then
    -- Only one solution, just use it
    M.selected_solution = solutions[1]
    M.write_cache(root, solutions[1])
    M.restart_omnisharp()
    vim.notify('Selected solution: ' .. vim.fn.fnamemodify(solutions[1], ':t'))
    return
  end

  -- Multiple solutions - show Telescope picker
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  -- Create relative paths for display
  local items = {}
  for _, solution in ipairs(solutions) do
    local relative = vim.fn.fnamemodify(solution, ':~:.')
    table.insert(items, {
      display = relative,
      path = solution
    })
  end

  pickers.new({}, {
    prompt_title = 'Select OmniSharp Solution',
    finder = finders.new_table({
      results = items,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()

        if selection then
          local solution_path = selection.value.path
          M.selected_solution = solution_path
          M.write_cache(root, solution_path)
          M.restart_omnisharp()
          vim.notify('Selected solution: ' .. vim.fn.fnamemodify(solution_path, ':t'))
        end
      end)
      return true
    end,
  }):find()
end

-- Restart OmniSharp LSP client
function M.restart_omnisharp()
  local clients = vim.lsp.get_clients({ name = 'omnisharp' })

  if #clients == 0 then
    vim.notify('No OmniSharp client running', vim.log.levels.WARN)
    return
  end

  -- Stop all OmniSharp clients
  for _, client in ipairs(clients) do
    client.stop()
  end

  -- Wait a bit and restart
  vim.defer_fn(function()
    vim.cmd('edit')
  end, 500)
end

return M
