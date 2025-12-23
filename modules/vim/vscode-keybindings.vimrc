" VSCode-Neovim extension general keybindings
source $HOME/.modules/vim/vscode-base-keybindings.vimrc
lua require('vscode-keybinding-settings')
lua require('sql-cleanup')

" VSCode-specific
nnoremap gK  :call VSCodeNotify('editor.debug.action.showDebugHover')<CR>
nnoremap gH   :call VSCodeNotify('editor.debug.action.showDebugHover')<CR>
nnoremap gi   :call VSCodeNotify('editor.action.goToImplementation')<CR>
nnoremap gr   :call VSCodeNotify('editor.action.goToReferences')<CR>
nnoremap <Leader>t   :call VSCodeNotify('dotnet.test.runTestsInContext')<CR>
nnoremap <Leader>d   :call VSCodeNotify('dotnet.test.debugTestsInContext')<CR>
nnoremap <Leader>e   :call VSCodeNotify('workbench.view.explorer')<CR>

" Reset VS Code
nnoremap <Leader>R   :call VSCodeNotify('workbench.action.reloadWindow')<CR>

" TODO: define some mapping for this
" nnoremap <Leader>y   :call VSCodeNotify('editor.emmet.action.expandAbbreviation')<CR>
