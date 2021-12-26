" Remove the showmode bar since it's unnecessary now
set noshowmode
set laststatus=2

" Add diagnostic info for https://github.com/itchyny/lightline.vim
let g:lightline = {
\ 'colorscheme': 'wombat',
\ 'active': {
\   'left': [
\     [ 'mode', 'paste' ],
\     [ 'cocstatus', 'readonly', 'relativepath', 'modified' ]
\   ],
\   'right':[
\     [ 'filetype', 'fileencoding', 'lineinfo', 'percent' ],
\     [ 'blame' ]
\   ],
\ },
\ 'component_function': {
\   'cocstatus': 'coc#status',
\   'blame': 'LightlineGitBlame'
\ },
\ }

function! LightlineGitBlame() abort
  let blame = get(b:, 'coc_git_blame', '')
  " return blame
  return winwidth(0) > 120 ? blame : ''
endfunction

