printf "\n->> Profile settings"
if grep -q "source $HOME/.shell/profile" "$HOME/.profile"; then
  printf "\n-->> Profile settings already set"
else
  printf "\n-->> Writing profile settings"
  printf "source $HOME/.shell/profile" >> "$HOME/.profile"
fi

printf "\n-->> Creating .shell folder"
SHELL_PROFILE = $(dirname "$0")
mkdir -p "$HOME/.shell"

printf "\n->> Setting environment variables"
printf "\n-->> Set the value for GIT_USERNAME: "
read GIT_USERNAME
printf "\n-->> Set the value for GIT_EMAIL: "
read GIT_EMAIL
printf "export GIT_USERNAME=\"$GIT_USERNAME\"\n\
export GIT_EMAIL=\"$GIT_EMAIL\"\n" > "$HOME/.shell/profile"

