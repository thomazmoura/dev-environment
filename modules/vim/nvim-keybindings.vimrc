"  Back to previous page
nnoremap <Leader><Tab> :b#<CR>

" * Turn off highlighing with ESC
nnoremap <esc> :noh<CR>

" Save on Leader Leader
nnoremap <Leader><Leader> :w<CR>

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

" Telescope
nnoremap <Leader>/ <cmd>Telescope find_files<cr>
nnoremap <Leader>* <cmd>Telescope live_grep<cr>
nnoremap <Leader>? <cmd>Telescope buffers<cr>
nnoremap <Leader>h <cmd>Telescope help_tags<cr>
nnoremap <Leader>, <cmd>Telescope find_files cwd=~/code/dotfiles<cr>

" FZF
nnoremap <C-p> :Files<CR>
nnoremap <Leader><C-p> :Buffers<CR>
nnoremap <C-t> :CocFzfList symbols<CR>
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

" Insert a GUID/UUID
nnoremap <Leader>gg  mz<cmd>r!/opt/microsoft/powershell/7/pwsh -NoProfile -C "(New-Guid).Guid"<CR>y$dd`z"0p
nnoremap <Leader>gG  mz<cmd>r!/opt/microsoft/powershell/7/pwsh -NoProfile -C "(New-Guid).Guid"<CR>y$dd`z"0P

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

" Macros
" C# - Class boilerplate
nnoremap <leader>mn inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic class 0F/ldBf.Do{o}O
nnoremap <leader>mN inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic class 0F/ldBf.Do{o}gg$xji{Go}>i{jo
nnoremap <leader>mi inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic interface 0F/ldBf.Do{o}O
nnoremap <leader>mI inamespace "=fnamemodify(expand("%"), ":~:.")pyiW$F/D:s/\//./gA;ooipublic interface 0F/ldBf.Do{o}gg$xji{Go}>i{jo
" C# - Add parameter injection
nnoremap <leader>mp @="\"zyiwb\"xyiw?(\<lt>CR>Oprivate\<lt>Space>readonly\<lt>Space>\<lt>Esc>\"xpa\<lt>Space>\<lt>Esc>\"zpbi_\<lt>Esc>A;\<lt>Esc>/{\<lt>CR>%O\<lt>Esc>\"zpI_\<lt>Esc>A\<lt>Space>=\<lt>Space>\<lt>Esc>\"zpA;\<lt>Esc>=="<CR>
nnoremap <leader>mP @="\"zyiwbva>ob\"xyE?(\<lt>CR>Oprivate\<lt>Space>readonly\<lt>Space>\<lt>Esc>\"xpa\<lt>Space>\<lt>Esc>\"zpbi_\<lt>Esc>A;\<lt>Esc>/{\<lt>CR>%O\<lt>Esc>\"zpI_\<lt>Esc>A\<lt>Space>=\<lt>Space>\<lt>Esc>\"zpA;\<lt>Esc>=="<CR>
" C# - Convert SQL Column to C# property (n - supported)
nnoremap <leader>ms @="^Wdi]^Pa\<lt>Space>\<lt>Esc>wdi]hPlD:s/numeric/decimal/e\<lt>CR>:s/bit/bool/e\<lt>CR>:s/nvarchar/string/e\<lt>CR>:s/varchar/string/e\<lt>CR>:s/float/double/e\<lt>CR>:s/datetime2/datetime/e\<lt>CR>:s/bigint/float/e\<lt>CR>:s/text/string/e\<lt>CR>:s/datetime/DateTime/e\<lt>CR>A\<lt>Space>{\<lt>Space>get;\<lt>Space>set;\<lt>Space>}\<lt>Esc>Ipublic\<lt>Space>\<lt>Esc>j"<CR>
" C# - Merge SQL mapping and C# properties (n - supported)
nnoremap <leader>mc @="^d2Wf{hDIbuilder.Property(\<lt>Esc>\"0pa\<lt>Space>=>\<lt>Space>\<lt>Esc>\"0pa.\<lt>Esc>A)\<lt>Esc>o.HasColumnName();\<lt>Esc>hi\"\"\<lt>Esc>mz}j^\"zyi]dd`z^f\"\"0\"zpj"<CR>
" C# - Sort Global usings
nnoremap <leader>mu @="Gp:g/^$/d\<lt>CR>:g/^using/normal Iglobal \<lt>CR>:sort u\<lt>CR>"<CR>
nnoremap <leader>mU @=":b#\<lt>CR>ggdap:b#\<lt>CR>Gp:g/^$/d\<lt>CR>:g/^using/normal Iglobal \<lt>CR>:sort u\<lt>CR>:b#\<lt>CR>:wa\<lt>CR>"<CR>

" Copilot
imap <silent><script><expr> <End> copilot#Accept("\<CR>")
