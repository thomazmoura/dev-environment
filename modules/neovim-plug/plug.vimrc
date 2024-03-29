call plug#begin('~/.local/share/nvim/site/.plugged')

" Lua requirements
Plug 'nvim-lua/plenary.nvim'
Plug 'lewis6991/impatient.nvim'
Plug 'nvim-telescope/telescope.nvim', { 'branch': '0.1.x' }

" General Settings
Plug 'preservim/nerdcommenter'
Plug 'wellle/targets.vim'
Plug 'tpope/vim-eunuch'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-fugitive'
Plug 'lewis6991/gitsigns.nvim'
Plug 'thomazmoura/auto-save.nvim' 
Plug 'gorbit99/codewindow.nvim'
Plug 'github/copilot.vim'
Plug 'ThePrimeagen/harpoon'

" LSP and AutoComplete configuration
Plug 'L3MON4D3/LuaSnip', {'tag': 'v1.*'}
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-cmdline'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/nvim-cmp'
Plug 'neovim/nvim-lspconfig' 
Plug 'rafamadriz/friendly-snippets'
Plug 'saadparwaiz1/cmp_luasnip'
Plug 'windwp/nvim-autopairs'
Plug 'simrat39/symbols-outline.nvim'
Plug 'ErichDonGubler/lsp_lines.nvim'
Plug 'artempyanykh/marksman'
Plug 'aca/emmet-ls'

" Telescope
Plug 'BurntSushi/ripgrep'
Plug 'nvim-telescope/telescope-fzf-native.nvim', { 'do': 'make' }

" Jump motion
Plug 'phaazon/hop.nvim'

" General Settings
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'luochen1990/rainbow'
Plug 'nvim-lualine/lualine.nvim'
Plug 'karb94/neoscroll.nvim'

" TMUX integration
Plug 'christoomey/vim-tmux-navigator'
Plug 'tmux-plugins/vim-tmux-focus-events'
Plug 'roxma/vim-tmux-clipboard'
Plug 'aserowy/tmux.nvim'

" Colorschemes
Plug 'joshdick/onedark.vim'
Plug 'rakr/vim-one'
Plug 'folke/tokyonight.nvim', { 'branch': 'main' }
Plug 'catppuccin/nvim'
Plug 'levouh/tint.nvim'

" Highlighting
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'nvim-treesitter/nvim-treesitter-textobjects'

" Tree Explorer
Plug 'kyazdani42/nvim-web-devicons'
Plug 'kyazdani42/nvim-tree.lua'

call plug#end()


