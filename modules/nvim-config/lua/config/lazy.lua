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

require('lazy').setup({
  spec = { { import = 'plugins' } },
  defaults = {
    -- Under VS Code only the specs that set `cond = true` load (text objects,
    -- surround and the like); everything else is the terminal NeoVim's
    cond = not vim.g.vscode,
  },
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
