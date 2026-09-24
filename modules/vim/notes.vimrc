" The Notes pane's NeoVim (tmux layout, prefix+t, n): as bare as nvim -u NORC,
" plus just two things from the full vimrc -- moving between tmux panes and a
" transparent background.

" No plugins but vim-tmux-navigator, the one vim-plug installed for the vimrc.
set noloadplugins
set runtimepath^=~/.local/share/nvim/site/.plugged/vim-tmux-navigator
runtime plugin/tmux_navigator.vim

" Write all buffers before navigating from Vim to tmux pane
let g:tmux_navigator_save_on_switch = 2

" Transparent background
highlight Normal guibg=none ctermbg=none
highlight NormalNC guibg=none ctermbg=none
