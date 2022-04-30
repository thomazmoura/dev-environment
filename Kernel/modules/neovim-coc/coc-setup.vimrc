" COC.NVIM default settings
source $HOME/.vim/coc-config.vimrc

call plug#begin('~/.vim/.plugged')
Plug 'neoclide/coc.nvim', {'branch': 'release'}
call plug#end()

" COC.NVIM install configured modules
source $HOME/.modules/coc-modules.vimrc
