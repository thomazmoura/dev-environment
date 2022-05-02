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

#  Delta configuration
git config --global core.pager 'delta'
git config --global interactive.diffFilter 'delta --color-only --features=interactive'
git config --global delta.navigate 'true'
git config --global merge.conflictstyle 'diff3'
git config --global diff.colorMoved 'default'
git config --global delta.features 'decorations'
git config --global delta.interactive.keep-plus-minus-markers 'false'
git config --global delta.decorations.commit-decoration-style 'blue ol'
git config --global delta.decorations.commit-style 'raw'
git config --global delta.decorations.file-style 'omit'
git config --global delta.decorations.hunk-header-decoration-style 'blue box'
git config --global delta.decorations.hunk-header-file-style 'red'
git config --global delta.decorations.hunk-header-line-number-style '"#067a00"'
git config --global delta.decorations.hunk-header-style 'file line-number syntax'

