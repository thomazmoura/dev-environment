" vim-dadbod's postgresql adapter, with the passwords kept in locksmith.nvim. The vim-dadbod
" spec in lua/plugins/database.lua points postgresql: URLs here (g:db_adapter_postgresql).
" Each function calls dadbod's own with the URL's password filled in by
" lua/config/dadbod_locksmith.lua: none when the server lets the login in without one, else
" saved, or asked once and saved when the server takes it.
" Every function of dadbod's adapter needs one here: dadbod finds none it does not list.

function! s:with_password(url) abort
  let url = v:lua.require'config.dadbod_locksmith'.with_password(a:url)
  if url is v:null
    throw 'DB: no password typed for ' . a:url
  endif
  return url
endfunction

" When dadbod asks for the password itself: a refused login only, not any error with "auth"
" in it (its default, auth\|login, also takes psql's GSSAPI notices)
function! postgresql_locksmith#auth_pattern() abort
  return 'password authentication failed\|no password supplied'
endfunction

function! postgresql_locksmith#canonicalize(url) abort
  return db#adapter#postgresql#canonicalize(a:url)
endfunction

function! postgresql_locksmith#interactive(url, ...) abort
  return call('db#adapter#postgresql#interactive', [s:with_password(a:url)] + a:000)
endfunction

function! postgresql_locksmith#filter(url) abort
  return db#adapter#postgresql#filter(s:with_password(a:url))
endfunction

function! postgresql_locksmith#input(url, in) abort
  return db#adapter#postgresql#input(s:with_password(a:url), a:in)
endfunction

function! postgresql_locksmith#complete_database(url) abort
  return db#adapter#postgresql#complete_database(s:with_password(a:url))
endfunction

" No URL: the server psql reaches by default
function! postgresql_locksmith#complete_opaque(url) abort
  return db#adapter#postgresql#complete_opaque(a:url)
endfunction

function! postgresql_locksmith#tables(url) abort
  return db#adapter#postgresql#tables(s:with_password(a:url))
endfunction
