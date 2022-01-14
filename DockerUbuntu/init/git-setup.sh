git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"
git config --global core.editor 'nvim -u NORC'
git config --global alias.undo '!git checkout --force -- .; git clean -fd'
git config --global alias.history "log --oneline --graph --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s' --date=short --author-date-order"
git config --global alias.conflicts 'diff --name-only --diff-filter=U'
git config --global alias.clean-code 'clean -fxde .vscode'
git config --global push.default simple
git config --global core.quotepath off
git config --global fetch.prune true
git config --global core.excludesFile $HOME/.shell/gitignore
