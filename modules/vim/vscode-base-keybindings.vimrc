let g:EasyMotion_do_mapping = 0

" Folds
nnoremap zc   :call VSCodeNotify('editor.fold')<CR>
nnoremap zC   :call VSCodeNotify('editor.foldRecursively')<CR>
nnoremap zo   :call VSCodeNotify('editor.unfold')<CR>
nnoremap zO   :call VSCodeNotify('editor.unfoldRecursively')<CR>
nnoremap zM   :call VSCodeNotify('editor.foldAll')<CR>
nnoremap zR   :call VSCodeNotify('editor.unfoldAll')<CR>

" General editor keybindings
nnoremap K  :call VSCodeNotify('editor.action.showHover')<CR>
nnoremap <Leader><Leader> :call VSCodeNotify('workbench.action.files.save')<CR>
nnoremap <Leader>w :call VSCodeNotify('workbench.action.files.save')<CR>
nnoremap <leader>.   :call VSCodeNotify('editor.action.quickFix')<CR>
nnoremap <leader>x   :call VSCodeNotify('workbench.action.closeActiveEditor')<CR>
nnoremap <leader>f   :call VSCodeNotify('editor.action.formatDocument')<CR>
nnoremap <leader>F   :call VSCodeNotify('editor.action.formatChanges')<CR>
nnoremap <leader>h   :call VSCodeNotify('editor.action.wordHighlight.trigger')<CR>
nnoremap <leader>o   :call VSCodeNotify('outline.focus')<CR>
nnoremap <leader><CR>   :call VSCodeNotify('workbench.action.keepEditor')<CR>
nnoremap <leader><esc>   :call VSCodeNotify('notifications.clearAll')<CR>
nnoremap <leader>c<leader>   :call VSCodeNotify('editor.action.commentLine')<CR>
nnoremap <leader>cc   :call VSCodeNotify('editor.action.addCommentLine')<CR>
nnoremap <leader>cu   :call VSCodeNotify('editor.action.removeCommentLine')<CR>
nnoremap <Leader><Tab> :call VSCodeNotify('workbench.action.openPreviousRecentlyUsedEditor')<CR>
nnoremap <Leader><S-Tab> :call VSCodeNotify('workbench.action.openNextRecentlyUsedEditor')<CR>
nnoremap <Leader>/ :call VSCodeNotify('workbench.action.quickOpen')<CR>
nnoremap <Leader>? :call VSCodeNotify('workbench.action.quickOpen')<CR>

" Navigate through groups
nnoremap <C-h> :call VSCodeNotify('workbench.action.focusLeftGroup')<CR>
nnoremap <C-l> :call VSCodeNotify('workbench.action.focusRightGroup')<CR>
nnoremap <C-j> :call VSCodeNotify('workbench.action.focusBelowGroup')<CR>
nnoremap <C-k> :call VSCodeNotify('workbench.action.focusAboveGroup')<CR>

" Navigate through warnings and errors
nnoremap ]q   :call VSCodeNotify('editor.action.marker.nextInFiles')<CR>
nnoremap [q   :call VSCodeNotify('editor.action.marker.prevInFiles')<CR>

" Reset highlighting
nnoremap <esc> :noh<CR>

" Easy Motion
map <Leader>s <Plug>(easymotion-bd-f)
map <Leader>S <Plug>(easymotion-bd-t)
map gj <Plug>(easymotion-bd-f)
map gJ <Plug>(easymotion-bd-t)
map <Leader>j <Plug>(easymotion-j)
map <Leader>k <Plug>(easymotion-k)

" Navigate through buffers
nmap gb gt
nmap gB gT

" Deal with buffers
nnoremap <Leader>bd :bd<CR>
nnoremap <Leader>bD :bd#<CR>

" Swap selection with deleted contents
vnoremap gs p2g;P

" Search for selected text, forwards or backwards.
vnoremap <silent> * :<C-U>
  \let old_reg=getreg('"')<Bar>let old_regtype=getregtype('"')<CR>
  \gvy/<C-R>=&ic?'\c':'\C'<CR><C-R><C-R>=substitute(
  \escape(@", '/\.*$^~['), '\_s\+', '\\_s\\+', 'g')<CR><CR>
  \gVzv:call setreg('"', old_reg, old_regtype)<CR>
vnoremap <silent> # :<C-U>
  \let old_reg=getreg('"')<Bar>let old_regtype=getregtype('"')<CR>
  \gvy?<C-R>=&ic?'\c':'\C'<CR><C-R><C-R>=substitute(
  \escape(@", '?\.*$^~['), '\_s\+', '\\_s\\+', 'g')<CR><CR>
  \gVzv:call setreg('"', old_reg, old_regtype)<CR>

" Insert a GUID/UUID
nnoremap <Leader>gg  mz<cmd>r!pwsh -NoProfile -C "(New-Guid).Guid"<CR>y$dd`z"0p
nnoremap <Leader>gG  mz<cmd>r!pwsh -NoProfile -C "(New-Guid).Guid"<CR>y$dd`z"0P

" Use <Leader> as a substitute for "+ on yank and paste
noremap <Leader>y "+y
noremap <Leader>p "+p
noremap <Leader>Y "+Y
noremap <Leader>P "+P

" Use <Leader>0 as a substitute for "0 on some actions
noremap <Leader>0p "0p
noremap <Leader>0P "0P
noremap <Leader>0d "0d

" Quickly split vertically
nnoremap <Leader>\  :vsplit<CR>

" Quickly break the line
nnoremap <Leader><CR>  i<CR><ESC>

" Quickly sort (removing duplicates)
vnoremap <Leader>s :'<,'>sort u<CR>

" Use the arrows to scroll up and down
noremap <Down> <C-e>
noremap <Up> <C-y>

" Upper U as redo
nnoremap U <C-r>

set nocursorline
set nocursorcolumn
