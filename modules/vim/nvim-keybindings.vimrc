"  Back to previous page
nnoremap <silent> <Leader><Tab> :b#<CR>

" * Turn off highlighing with ESC
nnoremap <silent> <esc> :noh<CR>:Noice dismiss<CR>

" Save on Leader Leader
nnoremap <silent> <Leader><Leader> :w<CR>

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
nnoremap <silent> <C-e> :NvimTreeToggle<CR>
nnoremap <silent> <Leader><C-e> :NvimTreeFindFile<CR>
nnoremap <silent> <Leader>e :NvimTreeToggle<CR>

" Telescope
nnoremap <silent> <Leader>/ <cmd>Telescope find_files<cr>
nnoremap <silent> <Leader>* <cmd>Telescope live_grep<cr>
nnoremap <silent> <Leader>? <cmd>Telescope buffers<cr>
nnoremap <silent> <Leader>h <cmd>Telescope help_tags<cr>
nnoremap <silent> <Leader>, <cmd>Telescope find_files cwd=~/code/dotfiles<cr>

" Undotree
nnoremap <silent> <Leader>u <cmd>UndotreeToggle<cr><cmd>UndotreeFocus<cr>

" FZF
nnoremap <silent> <C-p> :Files<CR>
nnoremap <silent> <Leader><C-p> :Buffers<CR>

" Find everywhere
nnoremap <silent> <C-f> :Ag<CR>

" Delete the previous word
inoremap <silent> <C-BS> <C-w>
inoremap <silent> <C-h> <C-w>
cnoremap <silent> <C-BS> <C-w>
cnoremap <silent> <C-h> <C-w>

" Navigate through buffers
nnoremap <silent> gb :bnext<CR>
nnoremap <silent> gB :bprevious<CR>

" Navigate through quicklist
nnoremap <silent> <leader>] :cnext<CR>
nnoremap <silent> <leader>[ :cprevious<CR>

" Deal with buffers
nnoremap <silent> <Leader>bd :bd<CR>
nnoremap <silent> <Leader>bD :bd#<CR>

" Browsable command line history
nnoremap <silent> <leader>: q:i

" Force quit terminal
tnoremap <silent> <Leader><ESC> <C-\><C-N>

" Insert a GUID/UUID
nnoremap <silent> <Leader>gg  mz<cmd>r!uuidgen<CR>y$dd`z"0p
nnoremap <silent> <Leader>gG  mz<cmd>r!uuidgen<CR>y$dd`z"0P

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
nnoremap <silent> <Leader>\  :vsplit<CR>

" Quickly break the line
nnoremap <Leader><CR>  i<CR><ESC>

" Quickly sort (removing duplicates)
vnoremap <silent> <Leader>s :'<,'>sort u<CR>

" Use the arrows to scroll up and down
noremap <Down> <C-e>
noremap <Up> <C-y>

" Upper U as redo
nnoremap U <C-r>

" Show noice history
nnoremap <silent> <Leader>n :Telescope noice<CR>

" Toggle relative lines
nnoremap <silent> <Leader>L <CMD>set relativenumber!<CR>

" Macros
" C# - Class boilerplate
nnoremap <leader>mn inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic class 0F/ldBf.Do{o}O
nnoremap <leader>mN inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic class 0F/ldBf.Do{o}gg$xji{Go}>i{jo
nnoremap <leader>mi inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic interface 0F/ldBf.Do{o}O
nnoremap <leader>mI inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic interface 0F/ldBf.Do{o}gg$xji{Go}>i{jo
" C# - Add parameter injection
nnoremap <leader>mp @="\"zyiwb\"xyiw?(\<lt>CR>Oprivate\<lt>Space>readonly\<lt>Space>\<lt>Esc>\"xpa\<lt>Space>\<lt>Esc>\"zpbi_\<lt>Esc>A;\<lt>Esc>/{\<lt>CR>%O\<lt>Esc>\"zpI_\<lt>Esc>A\<lt>Space>=\<lt>Space>\<lt>Esc>\"zpA;\<lt>Esc>==:noh\<lt>CR>"<CR>
nnoremap <leader>mP @="\"zyiwbva>ob\"xyE?(\<lt>CR>Oprivate\<lt>Space>readonly\<lt>Space>\<lt>Esc>\"xpa\<lt>Space>\<lt>Esc>\"zpbi_\<lt>Esc>A;\<lt>Esc>/{\<lt>CR>%O\<lt>Esc>\"zpI_\<lt>Esc>A\<lt>Space>=\<lt>Space>\<lt>Esc>\"zpA;\<lt>Esc>==:noh\<lt>CR>"<CR>
" C# - Convert SQL Column to C# property (n - supported)
nnoremap <leader>ms @="^Wdi]^Pa\<lt>Space>\<lt>Esc>wdi]hPlD:s/numeric/decimal/e\<lt>CR>:s/bit/bool/e\<lt>CR>:s/nvarchar/string/e\<lt>CR>:s/varchar/string/e\<lt>CR>:s/float/double/e\<lt>CR>:s/datetime2/datetime/e\<lt>CR>:s/bigint/float/e\<lt>CR>:s/text/string/e\<lt>CR>:s/datetime/DateTime/e\<lt>CR>A\<lt>Space>{\<lt>Space>get;\<lt>Space>set;\<lt>Space>}\<lt>Esc>Ipublic\<lt>Space>\<lt>Esc>j"<CR>
" C# - Merge SQL mapping and C# properties (n - supported)
nnoremap <leader>mc @="^d2Wf{hDIbuilder.Property(\<lt>Esc>\"0pa\<lt>Space>=>\<lt>Space>\<lt>Esc>\"0pa.\<lt>Esc>A)\<lt>Esc>o.HasColumnName();\<lt>Esc>hi\"\"\<lt>Esc>mz}j^\"zyi]dd`z^f\"\"0\"zpj"<CR>
" C# - Sort Global usings
nnoremap <leader>mu @="Gp:g/^$/d\<lt>CR>:g/^using/normal Iglobal \<lt>CR>:sort u\<lt>CR>"<CR>
nnoremap <leader>mU @=":b#\<lt>CR>ggdap:b#\<lt>CR>Gp:g/^$/d\<lt>CR>:g/^using/normal Iglobal \<lt>CR>:sort u\<lt>CR>:b#\<lt>CR>:wa\<lt>CR>"<CR>
nnoremap <leader>mt ^Wyiwciwasync Task<0>f(%iCancellationToken cancellationToken
nnoremap <leader>mT ^Wyiwciwasync Task<0>f(%i, CancellationToken cancellationToken


" Copilot
if exists(':Copilot')
  imap <silent><script><expr> <End> copilot#Accept("\<CR>")
endif

