-- Bootstrap lazy.nvim and load every spec under lua/plugins
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    'git', 'clone', '--filter=blob:none', '--branch=stable',
    'https://github.com/folke/lazy.nvim.git', lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' }, { out } }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

-- Where this machine keeps its projects, as modules/tmux/scripts/code-folder.sh
-- decides: the first that exists of the setting steward.nvim writes
-- (~/.config/dev-environment/code-folder), $CODE_FOLDER, ~/code, ~/git and
-- /Git. $CODE_FOLDER alone is not enough: a shell can hand down one that does
-- not exist here (~/code on the company's machines, whose projects are in
-- /Git), and every plugin would then come from its old GitHub clone.
local function code_folder()
  local config = vim.env.XDG_CONFIG_HOME or vim.fn.expand('~/.config')
  local ok, lines = pcall(vim.fn.readfile, config .. '/dev-environment/code-folder', '', 1)
  local setting = ok and lines[1] or ''
  for _, candidate in ipairs({ setting, vim.env.CODE_FOLDER or '', '~/code', '~/git', '/Git' }) do
    if candidate ~= '' then
      local path = vim.fn.expand(candidate)
      if vim.fn.isdirectory(path) == 1 then
        return vim.fn.resolve(path)
      end
    end
  end
  return vim.fn.expand('~/code')
end

require('lazy').setup({
  spec = { { import = 'plugins' } },
  defaults = {
    -- Under VS Code only the specs that set `cond = true` load (text objects,
    -- surround and the like); everything else is the terminal NeoVim's
    cond = not vim.g.vscode,
  },
  -- My own plugins load from their checkout in the code folder when there is
  -- one (<code folder>/workhorse.nvim...), and from GitHub otherwise (Docker,
  -- other hosts), in code_folder() above (/Git on the company's machines)
  dev = { path = code_folder(), patterns = { 'thomazmoura' }, fallback = true },
  install = { colorscheme = { 'tokyonight-storm', 'habamax' } },
  -- Updates are deliberate (:Lazy update, then commit lazy-lock.json)
  checker = { enabled = false },
  change_detection = { notify = false },
  rocks = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = { 'gzip', 'tarPlugin', 'tohtml', 'tutor', 'zipPlugin' },
    },
  },
})
