. "$HOME/.modules/powershell/Check-Failure.ps1"

$NVS_HOME="$HOME/.nvs"
git clone https://github.com/jasongin/nvs $NVS_HOME --depth 1
chmod +x "$NVS_HOME/nvs.ps1"
. "$NVS_HOME/nvs.ps1" install

& "$NVS_HOME/nvs.ps1" add lts
& "$NVS_HOME/nvs.ps1" add lts
# ~/.nvs/default, the node every shell starts with: the bashrc puts its bin dir
# on PATH without launching nvs, and `nvs use auto` falls back to it when no
# .node-version is in scope. On Linux, `nvs link` only makes the symlink.
& "$NVS_HOME/nvs.ps1" link lts

Throw-ExceptionOnNativeFailure
