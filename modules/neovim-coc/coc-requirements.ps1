Write-Output "`n->> Installing pylint for coc-python"
& pip3 install pylint

Write-Output "`n->> Use LTS Node"
/home/developer/.nvs/nvs.ps1 use lts

Write-Output "`n->> Preinstalling coc-modules"
$CocModulesInstallCommand = "CocInstall -sync " +
  "coc-angular " +
  "coc-css " +
  "coc-clangd " +
  "coc-emmet " +
  "coc-eslint " +
  "coc-git " +
  "coc-html " +
  "coc-json " +
  "coc-powershell " +
  "coc-prettier " +
  "coc-python " +
  "coc-snippets " +
  "coc-tsserver " +
  "coc-yaml"
nvim -n -u /home/developer/.modules/neovim-coc/coc-setup.vimrc +"$CocModulesInstallCommand" +qall

