Write-Output "`n->> Installing Json Language Server"
npm install --global vscode-langservers-extracted

Write-Output "`n->> Installing tsserver - TypeScript Language Server"
npm install --global typescript typescript-language-server

Write-Output "`n->> Installing Angular Language Server"
npm install --global @angular/language-server

Write-Output "`n->> Installing YAML Language Server"
& npm install --global yaml-language-server

Write-Output "`n->> Installing VIM Language Server"
& npm install --global vim-language-server

