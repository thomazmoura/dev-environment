" Extends vim-dadbod's sqlserver adapter. Sourced by the vim-dadbod spec's config in
" lua/plugins/database.lua: Vim only allows db#adapter#sqlserver#* functions to be
" defined from a file whose path ends in db/adapter/sqlserver.vim, and after/ comes
" last in the runtimepath, so autoload still finds dadbod's file first.

" go-sqlcmd asks for a missing password through liner, which fails without a TTY
" ("liner: function not supported in this terminal"). Counting that as an auth
" failure makes dadbod prompt for the password and keep it for the session
function! db#adapter#sqlserver#auth_pattern() abort
  return 'auth\|login\|liner'
endfunction
