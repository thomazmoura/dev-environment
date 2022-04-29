call plug#begin('~/.vim/.plugged')

" General Settings
Plug 'preservim/nerdcommenter'
Plug 'wellle/targets.vim'
Plug 'tpope/vim-eunuch'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-repeat'
Plug 'machakann/vim-highlightedyank'

" HTML editing
Plug 'mattn/emmet-vim', { 'for': 'html' }

if !exists('g:vscode')
  " General Settings
  Plug 'christoomey/vim-tmux-navigator'
  Plug 'easymotion/vim-easymotion'
  Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
  Plug 'junegunn/fzf.vim'
  Plug 'preservim/nerdtree'
  Plug 'xuyuanp/nerdtree-git-plugin'
  Plug 'luochen1990/rainbow'
  Plug 'itchyny/lightline.vim'
  Plug 'sheerun/vim-polyglot'
  Plug 'tmux-plugins/vim-tmux-focus-events'
  Plug 'roxma/vim-tmux-clipboard'
  Plug 'antoinemadec/coc-fzf'

  " Overhaul
  Plug 'neoclide/coc.nvim', {'branch': 'release'}

  " Colorschemes
  Plug 'joshdick/onedark.vim'
else
  Plug 'asvetliakov/vim-easymotion', { 'dir': '~/.vim/.plugged/vim-easymotion-vscode' } 
endif

call plug#end()

