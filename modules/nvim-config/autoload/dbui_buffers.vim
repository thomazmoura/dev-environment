" dadbod-ui's Buffers list for lua/config/dbui_buffers.lua. The list lives in the drawer's
" dictionaries, which a call from Lua would only get a copy of, so it is changed from here.

" The drawer, or {} while DBUI was not opened yet
function! s:drawer() abort
  let drawer = db_ui#drawer#get()
  return has_key(drawer, 'dbui') ? drawer : {}
endfunction

" Takes file off a database's Buffers list (a query buffer that never ran)
function! dbui_buffers#remove(key, file) abort
  let drawer = s:drawer()
  if empty(drawer) || !has_key(drawer.dbui.dbs, a:key)
    return
  endif
  call filter(drawer.dbui.dbs[a:key].buffers.list, 'v:val !=# a:file')
  call drawer.render()
endfunction

" Puts file at the end of a database's Buffers list (a query that ran)
function! dbui_buffers#add(key, file) abort
  let drawer = s:drawer()
  if empty(drawer) || !has_key(drawer.dbui.dbs, a:key)
    return
  endif
  let buffers = drawer.dbui.dbs[a:key].buffers
  if index(buffers.list, a:file) == -1
    if empty(buffers.list)
      let buffers.expanded = 1
    endif
    call add(buffers.list, a:file)
  endif
  call drawer.render()
endfunction

" <Tab> in the drawer (after/ftplugin/dbui.lua): the buffer or saved query under the cursor
" opened in the query window, as <CR> does, with the cursor kept in the drawer
function! dbui_buffers#preview() abort
  let drawer = s:drawer()
  if empty(drawer)
    return
  endif
  let item = drawer.get_current_item()
  if get(item, 'action', '') !=# 'open' || get(item, 'type', '') !=# 'buffer'
    return
  endif
  let win = win_getid()
  call drawer.get_query().open(item, 'edit')
  call win_gotoid(win)
endfunction
