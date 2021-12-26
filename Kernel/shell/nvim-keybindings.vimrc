"  Back to previous page
nnoremap <Leader><C-i> :e#<CR>
" * Turn off highlighing with ESC
nnoremap <esc> :noh<CR>
"  NERDTree
nnoremap <C-e> :NERDTreeToggle<CR>
nnoremap <Leader><C-e> :NERDTreeFind<CR>
" Activate fzf
nnoremap <C-p> :Files<CR>
nnoremap <Leader><C-p> :Buffers<CR>
nnoremap <C-t> :CocFzfList symbols<CR>
" Find everywhere
nnoremap <C-f> :Ag<CR>
" Easymotion jump to character - easymotionprefix + s
nnoremap gj :<C-U>call EasyMotion#S(1,0,2)<CR>
" Delete the previous word
noremap! <C-BS> <C-w>
noremap! <C-h> <C-w>
