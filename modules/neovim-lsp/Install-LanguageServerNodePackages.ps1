function Install-NodePackageGlobally([string]$NpmGlobalPackages, [string]$PackageName) {
  if(!($NpmGlobalPackages -match $PackageName)) {
    Write-Output "`n->> Installing Json Language Server"
    npm install --global $PackageName
  } else {
    Write-Output "`n->> $PackageName already installed. Skipping."
  }

}

Write-Output "`n->> Getting installed packages"
$CurrentNpmGlobalPackages = & npm list --global --depth 0
Write-Output $CurrentNpmGlobalPackages

Install-NodePackageGlobally -NpmGlobalPackages $CurrentNpmGlobalPackages -PackageName 'vscode-langservers-extracted'
Install-NodePackageGlobally -NpmGlobalPackages $CurrentNpmGlobalPackages -PackageName 'typescript-language-server'
Install-NodePackageGlobally -NpmGlobalPackages $CurrentNpmGlobalPackages -PackageName '@angular/language-server'
Install-NodePackageGlobally -NpmGlobalPackages $CurrentNpmGlobalPackages -PackageName 'yaml-language-server'
Install-NodePackageGlobally -NpmGlobalPackages $CurrentNpmGlobalPackages -PackageName 'vim-language-server'

