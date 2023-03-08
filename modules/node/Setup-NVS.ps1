. "$HOME/.modules/powershell/Check-Failure.ps1"

$NVS_HOME="$HOME/.nvs"
git clone https://github.com/jasongin/nvs $NVS_HOME --depth 1
. "$NVS_HOME/nvs.ps1" install

nvs add lts
nvs use lts

Throw-ExceptionOnNativeFailure
