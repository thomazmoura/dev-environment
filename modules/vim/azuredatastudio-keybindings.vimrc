" VSCode-Neovim extension general keybindings
source $HOME/.modules/vim/vscode-base-keybindings.vimrc

" AzureDataStudio-specific
nnoremap <leader>r   :call VSCodeNotify('runCurrentQueryKeyboardAction')<CR>
vnoremap <leader>r   :call VSCodeNotify('runCurrentQueryKeyboardAction')<CR>
nnoremap <leader>R   :call VSCodeNotify('runQueryKeyboardAction')<CR>
vnoremap <leader>R   :call VSCodeNotify('runQueryKeyboardAction')<CR>
nnoremap <leader>j   :call VSCodeNotify('ToggleFocusBetweenQueryEditorAndResultsAction')<CR>
