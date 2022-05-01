"  Back to previous page
nnoremap <Leader><Tab> :b#<CR>

" * Turn off highlighing with ESC
nnoremap <esc> :noh<CR>

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

" File Explorer
nnoremap <C-e> :NvimTreeToggle<CR>
nnoremap <Leader><C-e> :NvimTreeFindFile<CR>

" Activate fzf
nnoremap <C-p> :Files<CR>
nnoremap <Leader><C-p> :Buffers<CR>
nnoremap <C-t> :CocFzfList symbols<CR>
nnoremap <Leader>/ :Files<CR>
nnoremap <Leader>? :Buffers<CR>
nnoremap <Leader>O :CocFzfList symbols<CR>

" Find everywhere
nnoremap <C-f> :Ag<CR>

" Format document
nnoremap <Leader>f :CocCommand editor.action.formatDocument<CR>
nnoremap <Leader>F :CocCommand prettier.formatFile<CR>

" Delete the previous word
noremap! <C-BS> <C-w>
noremap! <C-h> <C-w>

" Navigate through buffers
nnoremap gb :bnext<CR>
nnoremap gB :bprevious<CR>

" Reset Omnisharp
nnoremap <Leader>R :CocRestart<CR><CR>

" Deal with buffers
nnoremap <Leader>bd :bd<CR>
nnoremap <Leader>bD :bd#<CR>

" Browsable command line history
nnoremap <leader>: q:i

" Force quit terminal
tnoremap <Leader><ESC> <C-\><C-N>
