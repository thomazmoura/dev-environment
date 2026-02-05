call plug#begin('~/.local/share/nvim/site/.plugged')

" Lua requirements
Plug 'nvim-lua/plenary.nvim'
Plug 'lewis6991/impatient.nvim'
Plug 'nvim-telescope/telescope.nvim', { 'branch': '0.1.x' }
Plug 'MunifTanjim/nui.nvim'
Plug 'rcarriga/nvim-notify'
Plug 'folke/neodev.nvim'

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
Plug 'ThePrimeagen/harpoon'
Plug 'folke/which-key.nvim'
Plug 'mbbill/undotree'
Plug 'folke/trouble.nvim'
Plug 'arthurxavierx/vim-caser'

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
Plug 'https://git.sr.ht/~whynothugo/lsp_lines.nvim'
Plug 'artempyanykh/marksman'
Plug 'aca/emmet-ls'
Plug 'Hoffs/omnisharp-extended-lsp.nvim'
Plug 'williamboman/mason.nvim'
Plug 'tpope/vim-dadbod'
Plug 'kristijanhusak/vim-dadbod-ui'
Plug 'kristijanhusak/vim-dadbod-completion'
Plug 'radenling/vim-dispatch-neovim'

" Telescope
Plug 'BurntSushi/ripgrep'
Plug 'nvim-telescope/telescope-fzf-native.nvim', { 'do': 'make' }
Plug 'nvim-telescope/telescope-ui-select.nvim'

" Jump motion
Plug 'phaazon/hop.nvim'

" General Settings
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'luochen1990/rainbow'
Plug 'nvim-lualine/lualine.nvim'
Plug 'karb94/neoscroll.nvim'
Plug 'folke/noice.nvim'
Plug 'OXY2DEV/markview.nvim'

" TMUX integration
Plug 'christoomey/vim-tmux-navigator'
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

" Debugging
Plug 'mfussenegger/nvim-dap'
Plug 'rcarriga/nvim-dap-ui'
Plug 'theHamsta/nvim-dap-virtual-text'
Plug 'nvim-telescope/telescope-dap.nvim'
Plug 'nvim-neotest/nvim-nio'

" AI
Plug 'coder/claudecode.nvim'
" I'm currently trying the lua version of copilot
" Plug 'github/copilot.vim'
Plug 'zbirenbaum/copilot.lua'

" Mine
Plug '~/code/workhorse.nvim'
" Plug 'thomazmoura/workhorse.nvim'

call plug#end()

