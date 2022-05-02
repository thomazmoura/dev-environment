Write-Output "Setting git config for $env:GIT_USERNAME"
git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"
