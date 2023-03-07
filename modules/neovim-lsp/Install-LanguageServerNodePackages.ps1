Write-Output "`n->> Getting installed packages"
$CurrentNpmGlobalPackages = & npm list --global --depth 0
Write-Output $CurrentNpmGlobalPackages

if(!($CurrentNpmGlobalPackages -match 'vscode-langservers-extracted')) {
  Write-Output "`n->> Installing Json Language Server"
  npm install --global vscode-langservers-extracted
} else {
  Write-Output "`n->> vscode-langservers-extracted already installed. Skipping."
}

if(!($CurrentNpmGlobalPackages -match 'typescript-language-server')) {
  Write-Output "`n->> Installing tsserver - TypeScript Language Server"
  npm install --global typescript typescript-language-server
} else {
  Write-Output "`n->> typescript-language-server already installed. Skipping."
}

if(!($CurrentNpmGlobalPackages -match '@angular/language-server')) {
  Write-Output "`n->> Installing Angular Language Server"
  npm install --global @angular/language-server
} else {
  Write-Output "`n->> @angular/language-server already installed. Skipping."
}

if(!($CurrentNpmGlobalPackages -match 'yaml-language-server')) {
  Write-Output "`n->> Installing YAML Language Server"
  npm install --global yaml-language-server
  npm install --global yaml-language-service
} else {
  Write-Output "`n->> yaml-language-server already installed. Skipping."
}

if(!($CurrentNpmGlobalPackages -match 'vim-language-server')) {
  Write-Output "`n->> Installing VIM Language Server"
  npm install --global vim-language-server
} else {
  Write-Output "`n->> vim-language-server already installed. Skipping."
}

