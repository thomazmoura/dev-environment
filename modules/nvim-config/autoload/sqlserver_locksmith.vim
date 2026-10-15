" vim-dadbod's sqlserver adapter, with the passwords kept in locksmith.nvim. The vim-dadbod
" spec in lua/plugins/database.lua points sqlserver: URLs here (g:db_adapter_sqlserver).
" Each function calls dadbod's own with the URL's password filled in by
" lua/config/sqlserver_locksmith.lua: saved, or asked once and saved when the server takes it.
" Every function of dadbod's adapter needs one here: dadbod finds none it does not list.

" go-sqlcmd asks for a missing password through liner, which fails without a TTY, so the
" password always comes from here, in the URL (SQLCMDPASSWORD for sqlcmd)
function! s:with_password(url) abort
  let url = v:lua.require'config.sqlserver_locksmith'.with_password(a:url)
  if url is v:null
    throw 'DB: no password typed for ' . a:url
  endif
  return url
endfunction

" When dadbod asks for the password itself: a refused login only, not "Login timeout
" expired" (its default, auth\|login, takes an unreachable server for a wrong password)
function! sqlserver_locksmith#auth_pattern() abort
  return 'login failed'
endfunction

function! sqlserver_locksmith#canonicalize(url) abort
  return db#adapter#sqlserver#canonicalize(a:url)
endfunction

function! sqlserver_locksmith#interactive(url) abort
  return db#adapter#sqlserver#interactive(s:with_password(a:url))
endfunction

function! sqlserver_locksmith#input(url, in) abort
  return db#adapter#sqlserver#input(s:with_password(a:url), a:in)
endfunction

function! sqlserver_locksmith#dbext(url) abort
  return db#adapter#sqlserver#dbext(a:url)
endfunction

function! sqlserver_locksmith#complete_database(url) abort
  return db#adapter#sqlserver#complete_database(s:with_password(a:url))
endfunction

function! sqlserver_locksmith#tables(url) abort
  return db#adapter#sqlserver#tables(s:with_password(a:url))
endfunction
