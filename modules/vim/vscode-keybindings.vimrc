nnoremap K  :call VSCodeNotify('editor.action.showHover')<CR>
nnoremap gK  :call VSCodeNotify('editor.debug.action.showDebugHover')<CR>
nnoremap gH   :call VSCodeNotify('editor.debug.action.showDebugHover')<CR>
nnoremap gi   :call VSCodeNotify('editor.action.goToImplementation')<CR>
nnoremap zc   :call VSCodeNotify('editor.fold')<CR>
nnoremap zC   :call VSCodeNotify('editor.foldRecursively')<CR>
nnoremap zo   :call VSCodeNotify('editor.unfold')<CR>
nnoremap zO   :call VSCodeNotify('editor.unfoldRecursively')<CR>
nnoremap zM   :call VSCodeNotify('editor.foldAll')<CR>
nnoremap zR   :call VSCodeNotify('editor.unfoldAll')<CR>
nnoremap <leader>.   :call VSCodeNotify('editor.action.quickFix')<CR>
nnoremap <leader>y   :call VSCodeNotify('editor.emmet.action.expandAbbreviation')<CR>
nnoremap <leader>x   :call VSCodeNotify('workbench.action.closeActiveEditor')<CR>
nnoremap <leader>f   :call VSCodeNotify('editor.action.formatDocument')<CR>
nnoremap <leader>F   :call VSCodeNotify('editor.action.formatChanges')<CR>
nnoremap <leader>h   :call VSCodeNotify('editor.action.wordHighlight.trigger')<CR>
nnoremap <leader>r   :call VSCodeNotify('editor.action.rename')<CR>
nnoremap <leader>t   :call VSCodeNotify('dotnet.test.runTestsInContext')<CR>
nnoremap <leader>d   :call VSCodeNotify('dotnet.test.debugTestsInContext')<CR>
nnoremap <leader>o   :call VSCodeNotify('outline.focus')<CR>
nnoremap <leader><CR>   :call VSCodeNotify('workbench.action.keepEditor')<CR>
nnoremap <leader><esc>   :call VSCodeNotify('notifications.clearAll')<CR>
nnoremap ]q   :call VSCodeNotify('editor.action.marker.nextInFiles')<CR>
nnoremap [q   :call VSCodeNotify('editor.action.marker.prevInFiles')<CR>
nnoremap <leader>c<leader>   :call VSCodeNotify('editor.action.commentLine')<CR>
nnoremap <leader>cc   :call VSCodeNotify('editor.action.addCommentLine')<CR>
nnoremap <leader>cu   :call VSCodeNotify('editor.action.removeCommentLine')<CR>
nnoremap <Leader><C-i> :e#<CR>
nnoremap <esc> :noh<CR>
nnoremap  :call VSCodeNotify('workbench.action.focusLeftGroup')<CR>
nnoremap  :call VSCodeNotify('workbench.action.focusRightGroup')<CR>
nnoremap   :call VSCodeNotify('workbench.action.focusBelowGroup')<CR>
nnoremap  :call VSCodeNotify('workbench.action.focusAboveGroup')<CR>
