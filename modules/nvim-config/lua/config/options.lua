-- Editor options, shared by the terminal NeoVim and the VS Code profile
local opt = vim.opt

-- Line numbers and guides
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.cursorcolumn = true
opt.colorcolumn = '120'
opt.signcolumn = 'yes:1'

-- Wrapping and indentation (per-filetype exceptions live in after/ftplugin)
opt.linebreak = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true

-- Folding through tree-sitter, open up to 8 levels deep by default
opt.foldmethod = 'expr'
opt.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
opt.foldlevel = 8

-- The mode is in lualine (and noice), not the command line
opt.showmode = false
opt.laststatus = 2

opt.mouse = 'a'
opt.termguicolors = true
opt.guicursor = {
  'n-v-c:block',
  'i-ci-ve:ver25',
  'r-cr:hor20',
  'o:hor50',
  'a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor',
  'sm:block-blinkwait175-blinkoff150-blinkon175',
}
opt.fillchars:append({ vert = '│' })

-- Transparent floating windows and popup menu
opt.winblend = 15
opt.pumblend = 15

-- Swap files in the repo's (git-ignored) modules/vim/swapfiles, behind the
-- ~/.local/share/nvim/site symlink; DevHelpers.psm1 cleans them from there
opt.directory = vim.fn.stdpath('data') .. '/site/swapfiles/'

opt.wildignore:append({ '*.png', '*.jpg', '*/node_modules/**', '*/bin/**', '*/obj/**' })

-- No delay on <Esc>; which-key waits the default second for the rest
opt.ttimeoutlen = 0
opt.timeout = true
opt.timeoutlen = 1000

-- Disable modelines for security reasons
opt.modeline = false
