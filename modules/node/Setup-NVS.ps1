. "$HOME/.modules/powershell/Check-Failure.ps1"

$NVS_HOME="$HOME/.nvs"
git clone https://github.com/jasongin/nvs $NVS_HOME --depth 1
chmod +x "$NVS_HOME/nvs.ps1"
. "$NVS_HOME/nvs.ps1" install

& "$NVS_HOME/nvs.ps1" add lts
& "$NVS_HOME/nvs.ps1" add lts

Throw-ExceptionOnNativeFailure
