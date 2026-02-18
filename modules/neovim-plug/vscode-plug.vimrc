call plug#begin('~/.local/share/nvim/site/.plugged')

" Lua requirements
Plug 'nvim-lua/plenary.nvim'
Plug 'lewis6991/impatient.nvim'
Plug 'folke/neodev.nvim'

" General Settings
Plug 'preservim/nerdcommenter'
Plug 'wellle/targets.vim'
Plug 'tpope/vim-eunuch'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-fugitive'
Plug 'phaazon/hop.nvim'

" Mine
Plug '~/code/workhorse.nvim'

call plug#end()

